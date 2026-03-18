defmodule ElixirTAK.Transport.CotHandler do
  @moduledoc """
  ThousandIsland handler for TAK client TCP connections.

  Each connected client gets its own handler process. The handler:
  - Frames incoming bytes into complete events via `TakFramer` (auto-detects XML vs protobuf)
  - Parses and validates each event via `CotParser`/`ProtoParser` and `CotValidator`
  - Broadcasts valid events to all other clients via PubSub
  - Receives broadcasts from other clients and sends them to this socket
  - Initiates TAK protocol negotiation on connect (offers protobuf support)
  - Tracks per-client protocol mode (:xml or :protobuf) for encoding outbound events
  """

  use ThousandIsland.Handler

  require Logger

  alias ElixirTAK.Protocol.{
    CotEncoder,
    CotParser,
    CotValidator,
    Negotiation,
    ProtoEncoder,
    TakFramer
  }

  alias ElixirTAK.{
    ChatCache,
    ClientRegistry,
    GeofenceCache,
    History,
    MarkerCache,
    Metrics,
    RouteCache,
    SACache,
    ShapeCache,
    VideoCache
  }

  alias ElixirTAK.Protocol.GeofenceParser

  @pubsub ElixirTAK.PubSub
  @topic "cot:broadcast"

  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    peer = ThousandIsland.Socket.peername(socket)
    cert_cn = extract_cert_cn(socket)
    cert_serial = extract_cert_serial(socket)

    if cert_serial && ElixirTAK.CertStore.revoked?(cert_serial) do
      Logger.warning("Rejected revoked cert serial=#{cert_serial} from #{inspect(peer)}")
      {:close, %{}}
    else
      if cert_cn do
        Logger.info("TAK client connected: #{inspect(peer)} cert_cn=#{cert_cn}")
      else
        Logger.info("TAK client connected: #{inspect(peer)}")
      end

      Phoenix.PubSub.subscribe(@pubsub, @topic)

      replay_cached_events(socket)
      send_version_offer(socket)

      state = %{
        framer: TakFramer.new(),
        protocol: :xml,
        uid: nil,
        callsign: nil,
        group: nil,
        cert_cn: cert_cn,
        peer: peer
      }

      {:continue, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    {events, new_framer} = TakFramer.push(state.framer, data)
    state = %{state | framer: new_framer}
    state = process_events(events, socket, state)
    {:continue, state}
  end

  # IMPORTANT: handle_info is a raw GenServer callback, NOT a ThousandIsland.Handler callback.
  #
  # ThousandIsland's behaviour callbacks (handle_connection/2, handle_data/3, handle_close/2)
  # receive the socket as a separate argument and return {:continue, state}.
  #
  # But handle_info is GenServer.handle_info/2 — it receives {socket, state} as a single
  # tuple argument and must return {:noreply, {socket, state}}. Defining it as handle_info/3
  # will silently fail to match incoming messages, crashing the GenServer and closing the
  # client connection.
  def handle_info({:cot_broadcast, sender_uid, event, sender_group}, {socket, state}) do
    should_deliver =
      cond do
        sender_uid == state.uid -> false
        broadcast_type?(event.type) -> true
        state.group == nil -> true
        sender_group == nil -> true
        sender_group == state.group -> true
        true -> false
      end

    Logger.debug(
      "Relay #{event.type} from #{sender_uid} (group=#{sender_group}) to #{state.callsign || state.uid} (group=#{state.group}): deliver=#{should_deliver}"
    )

    if should_deliver do
      send_to_socket(socket, event, state)
    end

    {:noreply, {socket, state}}
  end

  def handle_info(:admin_disconnect, {socket, state}) do
    Logger.info("Admin force-disconnect: #{state.callsign || state.uid || inspect(state.peer)}")
    ThousandIsland.Socket.close(socket)
    {:noreply, {socket, state}}
  end

  def handle_info(_msg, {socket, state}) do
    {:noreply, {socket, state}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    SACache.delete(state.uid)
    ClientRegistry.unregister(state.uid)
    Logger.info("TAK client disconnected: #{state.callsign || state.uid || inspect(state.peer)}")
    :ok
  end

  # -- Private ----------------------------------------------------------------

  # Replay is always XML since it happens before negotiation completes.
  defp replay_cached_events(socket) do
    caches = [SACache, MarkerCache, ShapeCache, GeofenceCache, RouteCache, VideoCache, ChatCache]

    for cache <- caches, event <- cache.get_all() do
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      ThousandIsland.Socket.send(socket, xml)
    end
  end

  defp send_version_offer(socket) do
    offer = Negotiation.version_offer()
    xml = offer |> CotEncoder.encode() |> IO.iodata_to_binary()
    ThousandIsland.Socket.send(socket, xml)
  end

  defp handle_negotiation(%{type: "t-x-takp-q"} = event, socket, state) do
    version = Negotiation.requested_version(event)
    accepted = version != nil and Negotiation.supported_version?(version)

    # Send response as XML (negotiation happens before switching)
    response = Negotiation.version_response(accepted)
    xml = response |> CotEncoder.encode() |> IO.iodata_to_binary()
    ThousandIsland.Socket.send(socket, xml)

    if accepted do
      Logger.info(
        "Protocol negotiation: client #{state.callsign || state.uid || inspect(state.peer)} switched to protobuf v#{version}"
      )

      %{state | protocol: :protobuf, framer: TakFramer.switch_to_protobuf(state.framer)}
    else
      Logger.warning(
        "Protocol negotiation rejected: unsupported version #{inspect(version)} from #{inspect(state.peer)}"
      )

      state
    end
  end

  # Ignore other negotiation events (version offer echo, response echo)
  defp handle_negotiation(_event, _socket, state), do: state

  defp process_events([], _socket, state), do: state

  defp process_events([raw_event | rest], socket, state) do
    state =
      with {:ok, event} <- parse_framed_event(raw_event),
           {:ok, event} <- CotValidator.validate(event) do
        if Negotiation.negotiation_event?(event) do
          handle_negotiation(event, socket, state)
        else
          state = maybe_identify_client(event, state)
          state = maybe_update_group(event, state)

          broadcast_event(event, state)
          cache_event(event, state.group)
          Metrics.record_event(event.type)

          # Always store history as XML for consistency
          xml = ensure_xml(event, raw_event)
          History.Writer.record(event, xml, state.group)

          Logger.debug(
            "Event from #{state.callsign || state.uid}: type=#{event.type} group=#{state.group || "none"}"
          )

          state
        end
      else
        {:error, reason} ->
          Logger.warning(
            "Invalid event from #{state.callsign || state.uid || inspect(state.peer)}: #{inspect(reason)}"
          )

          state
      end

    process_events(rest, socket, state)
  end

  # Parse events from TakFramer output.
  # XML mode returns {:xml, xml_binary}, protobuf mode returns {:ok, event, payload}.
  defp parse_framed_event({:xml, xml}), do: CotParser.parse(xml)
  defp parse_framed_event({:ok, event, _payload}), do: {:ok, event}
  defp parse_framed_event({:error, _reason} = error), do: error

  # Ensure we have XML for history storage regardless of wire format.
  defp ensure_xml(_event, {:xml, xml}), do: xml

  defp ensure_xml(event, _raw) do
    event |> CotEncoder.encode() |> IO.iodata_to_binary()
  end

  defp extract_cert_serial(socket) do
    case ThousandIsland.Socket.peercert(socket) do
      {:ok, der_cert} ->
        tbs = elem(:public_key.pkix_decode_cert(der_cert, :otp), 1)
        elem(tbs, 2)

      {:error, _} ->
        nil
    end
  rescue
    _ -> nil
  end

  defp extract_cert_cn(socket) do
    case ThousandIsland.Socket.peercert(socket) do
      {:ok, der_cert} ->
        # OTPCertificate record: elem(1) = tbsCertificate
        # OTPTBSCertificate record: elem(6) = subject
        tbs = elem(:public_key.pkix_decode_cert(der_cert, :otp), 1)
        {:rdnSequence, rdn_list} = elem(tbs, 6)

        Enum.find_value(rdn_list, fn rdn_set ->
          Enum.find_value(rdn_set, fn
            {:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, cn}} -> to_string(cn)
            {:AttributeTypeAndValue, {2, 5, 4, 3}, {:printableString, cn}} -> to_string(cn)
            {:AttributeTypeAndValue, {2, 5, 4, 3}, cn} when is_list(cn) -> to_string(cn)
            {:AttributeTypeAndValue, {2, 5, 4, 3}, cn} when is_binary(cn) -> cn
            _ -> nil
          end)
        end)

      {:error, _} ->
        nil
    end
  rescue
    _ -> nil
  end

  defp maybe_update_group(event, state) do
    group_name =
      case event.detail do
        %{group: %{name: name}} when is_binary(name) and name != "" -> name
        _ -> nil
      end

    cond do
      group_name == nil ->
        state

      group_name == state.group ->
        state

      state.group == nil ->
        Logger.info("Client #{state.callsign || state.uid} joined group #{group_name}")
        ClientRegistry.update(state.uid, %{group: group_name})
        %{state | group: group_name}

      true ->
        Logger.info(
          "Client #{state.callsign || state.uid} changed group #{state.group} -> #{group_name}"
        )

        ClientRegistry.update(state.uid, %{group: group_name})
        %{state | group: group_name}
    end
  end

  defp broadcast_event(event, state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:cot_broadcast, state.uid, event, state.group})
  end

  defp cache_event(%{type: "a-" <> _} = event, group), do: SACache.put(event, group)
  defp cache_event(%{type: "b-m-p-" <> _} = event, group), do: MarkerCache.put(event, group)
  defp cache_event(%{type: "b-t-f" <> _} = event, _group), do: ChatCache.put(event)

  defp cache_event(%{type: "u-d-" <> _} = event, group) do
    if GeofenceParser.geofence_event?(event) do
      GeofenceCache.put(event, group)
    else
      ShapeCache.put(event, group)
    end
  end

  defp cache_event(%{type: "b-m-r" <> _} = event, group), do: RouteCache.put(event, group)
  defp cache_event(%{type: "b-i-v" <> _} = event, group), do: VideoCache.put(event, group)
  defp cache_event(%{type: "b-a-g" <> _}, _group), do: :ok
  defp cache_event(%{type: "t-x-d-d" <> _} = event, _group), do: handle_delete(event)
  defp cache_event(_event, _group), do: :ok

  defp handle_delete(%{raw_detail: raw}) when is_binary(raw) do
    case Regex.run(~r/<link[^>]*uid="([^"]+)"/, raw) do
      [_, target_uid] ->
        ShapeCache.delete(target_uid)
        GeofenceCache.delete(target_uid)
        RouteCache.delete(target_uid)
        MarkerCache.delete(target_uid)
        VideoCache.delete(target_uid)
        SACache.delete(target_uid)

      nil ->
        :ok
    end
  end

  defp handle_delete(_), do: :ok

  defp broadcast_type?("b-t-f" <> _), do: true
  defp broadcast_type?("b-a-o-" <> _), do: true
  defp broadcast_type?("b-a-g" <> _), do: true
  defp broadcast_type?("b-i-v" <> _), do: true
  defp broadcast_type?(_), do: false

  defp send_to_socket(socket, event, state) do
    payload = encode_for_client(event, state.protocol)

    case ThousandIsland.Socket.send(socket, payload) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send to #{state.callsign || state.uid}: #{inspect(reason)}")
    end
  end

  defp encode_for_client(event, :xml) do
    event |> CotEncoder.encode() |> IO.iodata_to_binary()
  end

  defp encode_for_client(event, :protobuf) do
    event |> ProtoEncoder.encode() |> TakFramer.frame_protobuf()
  end

  defp maybe_identify_client(event, %{uid: nil} = state) do
    callsign =
      case event.detail do
        %{callsign: cs} when is_binary(cs) -> cs
        _ -> nil
      end

    Logger.info(
      "Client identified: uid=#{event.uid} callsign=#{callsign || "unknown"} peer=#{inspect(state.peer)}"
    )

    ClientRegistry.register(event.uid, %{
      callsign: callsign,
      group: nil,
      peer: state.peer,
      cert_cn: state.cert_cn,
      handler_pid: self()
    })

    %{state | uid: event.uid, callsign: callsign}
  end

  defp maybe_identify_client(event, state) do
    # Update callsign if we get a newer one
    case event.detail do
      %{callsign: cs} when is_binary(cs) and cs != state.callsign ->
        %{state | callsign: cs}

      _ ->
        state
    end
  end
end
