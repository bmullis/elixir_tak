defmodule ElixirTAK.Federation.Manager do
  @moduledoc """
  Central coordinator for federation between ElixirTAK instances.

  Subscribes to `"cot:broadcast"`, filters events through `Policy`, wraps them
  in `FedEvent`, and sends to all connected peers via the configured transport.
  Inbound federated events are unwrapped, validated for loops/hops, and
  broadcast on the local PubSub so connected TAK clients see them.

  Loop prevention uses an ETS ordered_set of `{timestamp, uid, event_time}`
  tuples for recently-injected events. Events that the Manager itself injected
  are skipped on the outbound path. A periodic sweep cleans entries older than
  60 seconds.
  """

  use GenServer

  require Logger

  alias ElixirTAK.Federation.{FedEvent, Policy, ServerID}
  alias ElixirTAK.{ChatCache, MarkerCache, Metrics, RouteCache, SACache, ShapeCache}
  alias ElixirTAK.History

  @pubsub ElixirTAK.PubSub
  @cot_topic "cot:broadcast"
  @dashboard_topic "dashboard:events"

  @injected_table :federation_injected
  @cleanup_interval 30_000
  @injected_ttl_ms 60_000

  # -- Public API ------------------------------------------------------------

  @doc "Starts the federation manager."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Connect to a new peer via the configured transport."
  def add_peer(peer_config) do
    GenServer.call(__MODULE__, {:add_peer, peer_config})
  end

  @doc "Disconnect a peer."
  def remove_peer(peer_id) do
    GenServer.call(__MODULE__, {:remove_peer, peer_id})
  end

  @doc "List connected peers with status."
  def list_peers do
    GenServer.call(__MODULE__, :list_peers)
  end

  @doc "Return federation statistics."
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_opts) do
    server_uid = ServerID.get_or_create()
    config = Application.get_env(:elixir_tak, ElixirTAK.Federation, [])
    transport_mod = transport_module(config[:transport] || :beam)

    :ets.new(@injected_table, [:named_table, :public, :ordered_set])

    Phoenix.PubSub.subscribe(@pubsub, @cot_topic)
    schedule_cleanup()

    peers = config[:peers] || []

    Logger.info(
      "Federation manager started: server_uid=#{server_uid} transport=#{config[:transport] || :beam} peers=#{inspect(peers)}"
    )

    state = %{
      server_uid: server_uid,
      transport: transport_mod,
      peers: %{},
      stats: %{events_sent: 0, events_received: 0, per_peer: %{}}
    }

    # Connect to configured peers
    state = Enum.reduce(peers, state, fn peer, acc -> do_add_peer(acc, peer) end)

    {:ok, state}
  end

  # -- Outbound: local PubSub → federation peers

  @impl true
  def handle_info({:cot_broadcast, sender_uid, event, sender_group}, state) do
    state =
      cond do
        recently_injected?(event.uid, event.time) ->
          state

        not Policy.federate?(event) ->
          state

        true ->
          fed_event = FedEvent.wrap(event, state.server_uid, sender_uid, sender_group)
          state.transport.send_event(fed_event)
          update_outbound_stats(state)
      end

    {:noreply, state}
  end

  # -- Inbound: federation peers → local PubSub

  def handle_info({:fed_event, %FedEvent{} = fed_event}, state) do
    cond do
      fed_event.source_server == state.server_uid ->
        Logger.debug("Federation: dropping event that originated from this server")
        {:noreply, state}

      not FedEvent.should_forward?(fed_event) ->
        Logger.debug("Federation: dropping event at hop limit (#{fed_event.hop_count} hops)")
        {:noreply, state}

      true ->
        # Policy.accept?/2 is checked here when filtering is implemented
        event = fed_event.event
        mark_injected(event.uid, event.time)

        # Broadcast to local TAK clients
        Phoenix.PubSub.broadcast(
          @pubsub,
          @cot_topic,
          {:cot_broadcast, fed_event.sender_uid, event, fed_event.sender_group}
        )

        # Cache the event locally
        cache_federated_event(event, fed_event.sender_group)

        # Persist to history with source_server
        Metrics.record_event(event.type)

        History.Writer.record(
          event,
          event.raw_detail || "",
          fed_event.sender_group,
          source_server: fed_event.source_server
        )

        Logger.debug(
          "Federation: accepted event uid=#{event.uid} type=#{event.type} from #{fed_event.source_server}"
        )

        state = update_inbound_stats(state, fed_event.source_server)
        {:noreply, state}
    end
  end

  # -- Peer lifecycle notifications from transport

  def handle_info({:peer_connected, node}, state) do
    Logger.info("Federation: peer connected - #{node}")

    state =
      put_in(state, [:peers, node], %{
        status: :connected,
        connected_at: DateTime.utc_now()
      })

    broadcast_federation_status(state)
    {:noreply, state}
  end

  def handle_info({:peer_disconnected, node}, state) do
    Logger.warning("Federation: peer disconnected - #{node}")

    state =
      if Map.has_key?(state.peers, node) do
        put_in(state, [:peers, node, :status], :disconnected)
      else
        state
      end

    broadcast_federation_status(state)
    {:noreply, state}
  end

  # -- Cleanup timer

  def handle_info(:cleanup_injected, state) do
    cleanup_injected()
    schedule_cleanup()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Calls

  @impl true
  def handle_call({:add_peer, peer_config}, _from, state) do
    state = do_add_peer(state, peer_config)
    {:reply, :ok, state}
  end

  def handle_call({:remove_peer, peer_id}, _from, state) do
    state.transport.disconnect(peer_id)
    state = %{state | peers: Map.delete(state.peers, peer_id)}
    broadcast_federation_status(state)
    {:reply, :ok, state}
  end

  def handle_call(:list_peers, _from, state) do
    {:reply, state.peers, state}
  end

  def handle_call(:get_stats, _from, state) do
    connected_count =
      state.peers
      |> Enum.count(fn {_id, info} -> info.status == :connected end)

    stats = %{
      server_uid: state.server_uid,
      peers_configured: map_size(state.peers),
      peers_connected: connected_count,
      events_sent: state.stats.events_sent,
      events_received: state.stats.events_received
    }

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ets.delete(@injected_table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # -- Private ---------------------------------------------------------------

  defp transport_module(:beam), do: ElixirTAK.Federation.Transport.BEAM
  defp transport_module(:nats), do: ElixirTAK.Federation.Transport.NATS
  defp transport_module(mod) when is_atom(mod), do: mod

  defp do_add_peer(state, peer_config) do
    case state.transport.connect(peer_config) do
      {:ok, peer_id} ->
        Logger.info("Federation: connecting to peer #{inspect(peer_config)}")

        put_in(state, [:peers, peer_id], %{
          status: :connecting,
          connected_at: nil
        })

      {:error, reason} ->
        Logger.warning(
          "Federation: failed to connect to #{inspect(peer_config)}: #{inspect(reason)}"
        )

        state
    end
  end

  # -- Loop prevention via ETS ordered_set --

  defp mark_injected(uid, event_time) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@injected_table, {{now, uid, event_time}})
  end

  defp recently_injected?(uid, event_time) do
    cutoff = System.monotonic_time(:millisecond) - @injected_ttl_ms

    :ets.foldl(
      fn {{ts, u, t}}, acc ->
        if ts > cutoff and u == uid and t == event_time, do: true, else: acc
      end,
      false,
      @injected_table
    )
  end

  defp cleanup_injected do
    cutoff = System.monotonic_time(:millisecond) - @injected_ttl_ms

    # Delete all entries where timestamp < cutoff
    # In an ordered_set keyed by {timestamp, uid, event_time}, we can
    # select_delete entries with timestamp older than the cutoff
    :ets.select_delete(@injected_table, [
      {{{:"$1", :_, :_}}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_injected, @cleanup_interval)
  end

  # -- Caching federated events --

  defp cache_federated_event(%{type: "a-" <> _} = event, group), do: SACache.put(event, group)

  defp cache_federated_event(%{type: "b-m-p-" <> _} = event, group),
    do: MarkerCache.put(event, group)

  defp cache_federated_event(%{type: "b-t-f" <> _} = event, _group), do: ChatCache.put(event)

  defp cache_federated_event(%{type: "u-d-" <> _} = event, group),
    do: ShapeCache.put(event, group)

  defp cache_federated_event(%{type: "b-m-r" <> _} = event, group),
    do: RouteCache.put(event, group)

  defp cache_federated_event(_event, _group), do: :ok

  # -- Stats --

  defp update_outbound_stats(state) do
    update_in(state, [:stats, :events_sent], &(&1 + 1))
  end

  defp update_inbound_stats(state, source_server) do
    state
    |> update_in([:stats, :events_received], &(&1 + 1))
    |> update_in([:stats, :per_peer, source_server], fn
      nil -> %{received: 1}
      stats -> %{stats | received: stats.received + 1}
    end)
  end

  defp broadcast_federation_status(state) do
    connected_count =
      state.peers
      |> Enum.count(fn {_id, info} -> info.status == :connected end)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @dashboard_topic,
      {:federation_status,
       %{
         peers_configured: map_size(state.peers),
         peers_connected: connected_count
       }}
    )
  end
end
