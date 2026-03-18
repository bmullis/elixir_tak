defmodule ElixirTAKWeb.DashboardChannel do
  @moduledoc """
  Phoenix Channel for the React dashboard.

  On join, returns an initial snapshot of all cached state. Then forwards
  PubSub messages as channel pushes for real-time updates.

  COP overlay types (markers, shapes, routes, geofences) are parsed server-side
  and pushed as pre-parsed data via dedicated events (`upsert_marker`, etc.)
  alongside the raw `cot_event` for the events feed.
  """

  use Phoenix.Channel

  import Bitwise

  alias ElixirTAK.Protocol.{ChatParser, CotEvent, GeofenceParser, RouteParser, ShapeParser}

  alias ElixirTAK.{
    ChatCache,
    ClientRegistry,
    GeofenceCache,
    MarkerCache,
    Metrics,
    RouteCache,
    SACache,
    ShapeCache,
    VideoRegistry
  }

  @remarks_regex ~r/<remarks[^>]*>(.*?)<\/remarks>/s
  @emergency_element_regex ~r/<emergency[\s>]/
  @emergency_type_regex ~r/<emergency[^>]*type="([^"]+)"/
  @emergency_link_uid_regex ~r/<link[^>]*uid="([^"]+)"/
  @geofence_alert_ref_regex ~r/<__geofence[^>]*geofenceRef="([^"]+)"/

  @impl true
  def join("dashboard:cop", _params, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")
    Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "dashboard:events")

    snapshot = build_snapshot()
    push(socket, "snapshot", snapshot)

    # Push pre-parsed overlays separately
    overlays = build_parsed_overlays()
    push(socket, "parsed_overlays", overlays)

    {:noreply, socket}
  end

  # CoT broadcast from TAK clients — push raw event + parsed overlay if applicable
  def handle_info({:cot_broadcast, _sender_uid, %CotEvent{} = event, group}, socket) do
    push(socket, "cot_event", serialize_cot_event(event, group))

    # Push parsed chat message for chat events
    if String.starts_with?(event.type, "b-t-f") do
      case ChatParser.parse(event) do
        {:ok, msg} -> push(socket, "chat_message", serialize_chat_message(msg, group))
        :error -> :ok
      end
    end

    # Emergency events (b-a-o-*)
    try do
      if emergency_event?(event) do
        require Logger

        Logger.debug(
          "DashboardChannel: pushing emergency event type=#{event.type} uid=#{event.uid}"
        )

        push_emergency_event(socket, event)
      end

      # SA events may carry <emergency> in raw_detail while client has active emergency
      if sa_event?(event) do
        push_sa_emergency(socket, event)
      end

      # Geofence trigger alerts (b-a-g)
      if geofence_alert_event?(event) do
        push(socket, "geofence_triggered", build_geofence_alert(event))
      end
    rescue
      e ->
        require Logger
        Logger.error("DashboardChannel: emergency/geofence push failed: #{inspect(e)}")
    end

    # Push pre-parsed overlay events for COP types
    socket = push_parsed_overlay(socket, event)

    {:noreply, socket}
  end

  # Client connected
  def handle_info({:client_connected, uid, attrs}, socket) do
    push(socket, "client_connected", serialize_client(Map.put(attrs, :uid, uid)))
    {:noreply, socket}
  end

  # Client disconnected
  def handle_info({:client_disconnected, uid}, socket) do
    push(socket, "client_disconnected", %{uid: uid})
    {:noreply, socket}
  end

  # Metrics update (every 1s)
  def handle_info({:metrics_update, stats}, socket) do
    push(socket, "metrics", stats)
    {:noreply, socket}
  end

  # COP event deleted from dashboard
  def handle_info({:cop_event_deleted, uid, type}, socket) do
    event_name =
      case type do
        "marker" -> "remove_marker"
        "shape" -> "remove_shape"
        "route" -> "remove_route"
        _ -> nil
      end

    if event_name, do: push(socket, event_name, %{uid: uid})
    {:noreply, socket}
  end

  # Video stream events
  def handle_info({:video_stream_added, stream}, socket) do
    push(socket, "video_stream_added", serialize_video_stream(stream))
    {:noreply, socket}
  end

  def handle_info({:video_stream_updated, stream}, socket) do
    push(socket, "video_stream_updated", serialize_video_stream(stream))
    {:noreply, socket}
  end

  def handle_info({:video_stream_removed, uid}, socket) do
    push(socket, "video_stream_removed", %{uid: uid})
    {:noreply, socket}
  end

  def handle_info({:hls_status, uid, status}, socket) do
    push(socket, "hls_status", %{uid: uid, status: to_string(status)})
    {:noreply, socket}
  end

  # Ignore unknown messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- Incoming pushes from dashboard clients --

  @impl true
  def handle_in("send_chat", %{"message" => message, "callsign" => callsign}, socket) do
    now = DateTime.utc_now()
    sender_uid = "dashboard-#{System.unique_integer([:positive])}"
    chatroom = "All Chat Rooms"
    msg_id = :crypto.strong_rand_bytes(4) |> Base.encode16()
    chat_uid = "GeoChat.#{sender_uid}.#{chatroom}.#{msg_id}"

    event = %CotEvent{
      uid: chat_uid,
      type: "b-t-f",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: DateTime.add(now, 120, :second),
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{
        contact: %{callsign: callsign}
      },
      raw_detail: build_chat_detail(callsign, message, sender_uid, chatroom, now)
    }

    # Broadcast via PubSub so all handlers (including this channel) receive it
    Phoenix.PubSub.broadcast(
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, chat_uid, event, "All Chat Rooms"}
    )

    # Store in ChatCache
    ChatCache.put(event)

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("place_marker", params, socket) do
    now = DateTime.utc_now()
    uid = params["uid"] || "dashboard-marker-#{System.unique_integer([:positive])}"
    lat = params["lat"]
    lon = params["lon"]
    callsign = params["callsign"] || "Marker"
    remarks = params["remarks"]
    stale_minutes = params["stale_minutes"] || 60

    color = params["color"]
    marker_color = if color, do: css_color_to_argb(color), else: "-1"

    event = %CotEvent{
      uid: uid,
      type: "a-u-G",
      how: "h-e",
      time: now,
      start: now,
      stale: DateTime.add(now, stale_minutes * 60, :second),
      point: %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil},
      detail: %{contact: %{callsign: callsign}},
      raw_detail: build_marker_detail(callsign, remarks, marker_color)
    }

    MarkerCache.put(event)

    Phoenix.PubSub.broadcast(
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, uid, event, nil}
    )

    {:reply, {:ok, %{uid: uid}}, socket}
  end

  @impl true
  def handle_in("draw_shape", params, socket) do
    now = DateTime.utc_now()
    uid = params["uid"] || "dashboard-shape-#{System.unique_integer([:positive])}"
    name = params["name"] || "Shape"
    shape_type = params["shape_type"] || "polygon"
    vertices = params["vertices"] || []
    color = params["color"] || "rgba(0, 188, 212, 1)"
    remarks = params["remarks"]
    center = params["center"]
    radius = params["radius"]
    stale_minutes = params["stale_minutes"] || 1440

    cot_type =
      case shape_type do
        "circle" -> "u-d-c-c"
        "rectangle" -> "u-d-r"
        _ -> "u-d-f"
      end

    raw_detail = build_shape_detail(name, vertices, color, shape_type, center, radius, remarks)

    # For point, use center for circle or centroid for polygon
    {plat, plon} = shape_centroid(vertices, center)

    event = %CotEvent{
      uid: uid,
      type: cot_type,
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: DateTime.add(now, stale_minutes * 60, :second),
      point: %{lat: plat, lon: plon, hae: nil, ce: nil, le: nil},
      detail: %{contact: %{callsign: name}},
      raw_detail: raw_detail
    }

    ShapeCache.put(event)

    Phoenix.PubSub.broadcast(
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, uid, event, nil}
    )

    {:reply, {:ok, %{uid: uid}}, socket}
  end

  @impl true
  def handle_in("draw_route", params, socket) do
    now = DateTime.utc_now()
    uid = params["uid"] || "dashboard-route-#{System.unique_integer([:positive])}"
    name = params["name"] || "Route"
    waypoints = params["waypoints"] || []
    color = params["color"] || "rgba(0, 188, 212, 1)"
    remarks = params["remarks"]
    stale_minutes = params["stale_minutes"] || 1440

    raw_detail = build_route_detail(name, waypoints, color, remarks)

    {plat, plon} =
      case waypoints do
        [first | _] -> {first["lat"] || 0.0, first["lon"] || 0.0}
        _ -> {0.0, 0.0}
      end

    event = %CotEvent{
      uid: uid,
      type: "b-m-r",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: DateTime.add(now, stale_minutes * 60, :second),
      point: %{lat: plat, lon: plon, hae: nil, ce: nil, le: nil},
      detail: %{contact: %{callsign: name}},
      raw_detail: raw_detail
    }

    RouteCache.put(event)

    Phoenix.PubSub.broadcast(
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, uid, event, nil}
    )

    {:reply, {:ok, %{uid: uid}}, socket}
  end

  @impl true
  def handle_in("delete_cop_event", %{"uid" => uid, "type" => type}, socket) do
    case type do
      "marker" -> MarkerCache.delete(uid)
      "shape" -> ShapeCache.delete(uid)
      "route" -> RouteCache.delete(uid)
      _ -> :ok
    end

    # Broadcast removal to all dashboard channels
    Phoenix.PubSub.broadcast(
      ElixirTAK.PubSub,
      "dashboard:events",
      {:cop_event_deleted, uid, type}
    )

    {:reply, :ok, socket}
  end

  # -- Snapshot --

  @doc false
  def build_snapshot do
    chat_events = ChatCache.get_all()

    # ChatCache.get_all() returns newest first; reverse so client gets chronological order
    parsed_chat =
      chat_events
      |> Enum.reverse()
      |> Enum.map(fn event ->
        case ChatParser.parse(event) do
          {:ok, msg} ->
            group = get_in(event.detail || %{}, [:group, :name])
            serialize_chat_message(msg, group)

          :error ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    %{
      sa: SACache.get_all() |> Enum.map(&serialize_event/1),
      markers: MarkerCache.get_all() |> Enum.map(&serialize_event/1),
      shapes: ShapeCache.get_all() |> Enum.map(&serialize_event/1),
      routes: RouteCache.get_all() |> Enum.map(&serialize_event/1),
      geofences: GeofenceCache.get_all() |> Enum.map(&serialize_event/1),
      chat: chat_events |> Enum.map(&serialize_event/1),
      chat_messages: parsed_chat,
      clients: ClientRegistry.get_all() |> Enum.map(&serialize_client/1),
      metrics: Metrics.get_stats(),
      video_streams: VideoRegistry.list() |> Enum.map(&serialize_video_stream/1)
    }
  end

  # -- Parsed overlays for map display --

  defp build_parsed_overlays do
    %{
      markers: MarkerCache.get_all() |> Enum.map(&serialize_map_marker/1),
      shapes: ShapeCache.get_all() |> Enum.flat_map(&serialize_map_shape/1),
      routes: RouteCache.get_all() |> Enum.flat_map(&serialize_map_route/1),
      geofences: GeofenceCache.get_all() |> Enum.flat_map(&serialize_map_geofence/1)
    }
  end

  defp push_parsed_overlay(socket, %CotEvent{type: "b-m-p-" <> _} = event) do
    push(socket, "upsert_marker", serialize_map_marker(event))
    socket
  end

  defp push_parsed_overlay(socket, %CotEvent{type: "b-m-r" <> _} = event) do
    case serialize_map_route(event) do
      [route] -> push(socket, "upsert_route", route)
      [] -> :ok
    end

    socket
  end

  defp push_parsed_overlay(socket, %CotEvent{type: "u-d-" <> _} = event) do
    if GeofenceParser.geofence_event?(event) do
      case serialize_map_geofence(event) do
        [geofence] -> push(socket, "upsert_geofence", geofence)
        [] -> :ok
      end
    else
      case serialize_map_shape(event) do
        [shape] -> push(socket, "upsert_shape", shape)
        [] -> :ok
      end
    end

    socket
  end

  defp push_parsed_overlay(socket, _event), do: socket

  # -- Map overlay serializers --

  defp serialize_map_marker(%CotEvent{} = event) do
    %{
      uid: event.uid,
      lat: event.point.lat,
      lon: event.point.lon,
      callsign: get_callsign(event),
      remarks: extract_remarks(event.raw_detail),
      stale: CotEvent.stale?(event)
    }
  end

  defp serialize_map_shape(%CotEvent{} = event) do
    case ShapeParser.parse(event) do
      {:ok, shape} ->
        [
          %{
            uid: shape.uid,
            name: shape.name,
            shape_type: Atom.to_string(shape.shape_type),
            vertices: Enum.map(shape.vertices, fn {lat, lon} -> %{lat: lat, lon: lon} end),
            stroke_color: shape.stroke_color,
            fill_color: shape.fill_color,
            remarks: shape.remarks,
            center: shape_center(shape),
            radius: shape.radius,
            stale: CotEvent.stale?(event)
          }
        ]

      :error ->
        []
    end
  end

  defp serialize_map_route(%CotEvent{} = event) do
    case RouteParser.parse(event) do
      {:ok, route} ->
        [
          %{
            uid: route.uid,
            name: route.name,
            waypoints: Enum.map(route.waypoints, fn {lat, lon} -> %{lat: lat, lon: lon} end),
            waypoint_count: route.waypoint_count,
            total_distance_m: route.total_distance_m,
            stroke_color: route.stroke_color,
            remarks: route.remarks,
            stale: CotEvent.stale?(event)
          }
        ]

      :error ->
        []
    end
  end

  defp serialize_map_geofence(%CotEvent{} = event) do
    case GeofenceParser.parse(event) do
      {:ok, geofence} ->
        [
          %{
            uid: geofence.uid,
            name: geofence.name,
            shape_type: Atom.to_string(geofence.shape_type),
            vertices: Enum.map(geofence.vertices, fn {lat, lon} -> %{lat: lat, lon: lon} end),
            stroke_color: geofence.stroke_color,
            fill_color: geofence.fill_color,
            remarks: geofence.remarks,
            center: shape_center(geofence),
            radius: geofence.radius,
            trigger: geofence.trigger,
            monitor_type: geofence.monitor_type,
            boundary_type: geofence.boundary_type,
            stale: CotEvent.stale?(event)
          }
        ]

      :error ->
        []
    end
  end

  defp shape_center(%{shape_type: :circle, center: {lat, lon}}), do: %{lat: lat, lon: lon}

  defp shape_center(%{vertices: verts}) when length(verts) > 0 do
    count = length(verts)

    {sum_lat, sum_lon} =
      Enum.reduce(verts, {0.0, 0.0}, fn {lat, lon}, {al, ol} -> {al + lat, ol + lon} end)

    %{lat: sum_lat / count, lon: sum_lon / count}
  end

  defp shape_center(_), do: nil

  defp get_callsign(%{detail: %{callsign: cs}}) when is_binary(cs), do: cs
  defp get_callsign(%{detail: %{contact: %{callsign: cs}}}) when is_binary(cs), do: cs
  defp get_callsign(event), do: event.uid

  defp extract_remarks(nil), do: nil

  defp extract_remarks(raw_detail) do
    case Regex.run(@remarks_regex, raw_detail) do
      [_, text] when text != "" -> text
      _ -> nil
    end
  end

  # -- Raw event serializers --

  # All cache get_all() functions return bare %CotEvent{} structs.
  # Group is extracted from the detail map when available.
  defp serialize_event(%CotEvent{} = event) do
    group = get_in(event.detail || %{}, [:group, :name])

    %{
      uid: event.uid,
      type: event.type,
      how: event.how,
      time: format_dt(event.time),
      start: format_dt(event.start),
      stale: format_dt(event.stale),
      point: event.point,
      detail: event.detail,
      raw_detail: event.raw_detail,
      group: group
    }
  end

  defp serialize_cot_event(%CotEvent{} = event, group) do
    %{
      uid: event.uid,
      type: event.type,
      how: event.how,
      time: format_dt(event.time),
      start: format_dt(event.start),
      stale: format_dt(event.stale),
      point: event.point,
      detail: event.detail,
      raw_detail: event.raw_detail,
      group: group
    }
  end

  # Client attrs contain Erlang tuples (peer: {{127,0,0,1}, port}) and
  # DateTime structs that Jason can't encode directly.
  defp serialize_client(attrs) when is_map(attrs) do
    attrs
    |> Map.drop([:handler_pid])
    |> Map.update(:peer, nil, &format_peer/1)
    |> Map.update(:connected_at, nil, &format_dt/1)
  end

  defp format_peer({{a, b, c, d}, port}), do: "#{a}.#{b}.#{c}.#{d}:#{port}"
  defp format_peer(other), do: inspect(other)

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  # -- Chat helpers --

  defp serialize_chat_message(msg, group) do
    %{
      sender: msg.sender,
      chatroom: msg.chatroom,
      message: msg.message,
      sender_uid: msg.sender_uid,
      time: format_dt(msg.time),
      uid: msg.uid,
      group: group
    }
  end

  defp build_chat_detail(callsign, message, sender_uid, chatroom, time) do
    time_str = DateTime.to_iso8601(time)

    "<detail>" <>
      "<__chat parent=\"RootContactGroup\" groupOwner=\"false\" " <>
      "chatroom=\"#{escape_xml(chatroom)}\" id=\"#{escape_xml(chatroom)}\" " <>
      "senderCallsign=\"#{escape_xml(callsign)}\">" <>
      "<chatgrp uid0=\"#{sender_uid}\" uid1=\"#{escape_xml(chatroom)}\" id=\"#{escape_xml(chatroom)}\"/>" <>
      "</__chat>" <>
      "<link uid=\"#{sender_uid}\" type=\"a-f-G-U-C\" relation=\"p-p\"/>" <>
      "<remarks source=\"BAO.F.ATAK.#{sender_uid}\" sourceID=\"#{sender_uid}\" " <>
      "to=\"#{escape_xml(chatroom)}\" time=\"#{time_str}\">#{escape_xml(message)}</remarks>" <>
      "</detail>"
  end

  defp escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # -- COP drawing helpers --

  defp build_marker_detail(callsign, remarks, color_argb) do
    remarks_xml =
      if remarks && remarks != "",
        do: "<remarks>#{escape_xml(remarks)}</remarks>",
        else: ""

    "<detail>" <>
      "<contact callsign=\"#{escape_xml(callsign)}\"/>" <>
      "<color argb=\"#{color_argb}\"/>" <>
      "<precisionlocation altsrc=\"???\"/>" <>
      "<archive/>" <>
      remarks_xml <>
      "</detail>"
  end

  defp build_shape_detail(name, vertices, color, shape_type, center, radius, remarks) do
    stroke_color = css_color_to_argb(color)
    fill_color = css_color_to_argb_fill(color)

    links =
      vertices
      |> Enum.map(fn v ->
        lat = v["lat"] || 0.0
        lon = v["lon"] || 0.0
        "<link point=\"#{lat},#{lon},0.0\" />"
      end)
      |> Enum.join()

    # Close polygon by repeating first vertex
    closing_link =
      case {shape_type, vertices} do
        {"circle", _} -> ""
        {_, [first | _]} ->
          lat = first["lat"] || 0.0
          lon = first["lon"] || 0.0
          "<link point=\"#{lat},#{lon},0.0\" />"
        _ -> ""
      end

    ellipse_attrs =
      if shape_type == "circle" && center && radius do
        "<Shape ellipseMajor=\"#{radius}\" ellipseMinor=\"#{radius}\"/>"
      else
        ""
      end

    remarks_xml =
      if remarks && remarks != "",
        do: "<remarks>#{escape_xml(remarks)}</remarks>",
        else: ""

    "<detail>" <>
      "<contact callsign=\"#{escape_xml(name)}\"/>" <>
      "<strokeColor value=\"#{stroke_color}\"/>" <>
      "<fillColor value=\"#{fill_color}\"/>" <>
      links <>
      closing_link <>
      ellipse_attrs <>
      remarks_xml <>
      "</detail>"
  end

  defp build_route_detail(name, waypoints, color, remarks) do
    stroke_color = css_color_to_argb(color)

    links =
      waypoints
      |> Enum.map(fn wp ->
        lat = wp["lat"] || 0.0
        lon = wp["lon"] || 0.0
        "<link point=\"#{lat},#{lon},0.0\" relation=\"c\" />"
      end)
      |> Enum.join()

    remarks_xml =
      if remarks && remarks != "",
        do: "<remarks>#{escape_xml(remarks)}</remarks>",
        else: ""

    "<detail>" <>
      "<contact callsign=\"#{escape_xml(name)}\"/>" <>
      "<strokeColor value=\"#{stroke_color}\"/>" <>
      links <>
      remarks_xml <>
      "</detail>"
  end

  defp shape_centroid(_vertices, center) when is_map(center) do
    {center["lat"] || 0.0, center["lon"] || 0.0}
  end

  defp shape_centroid(vertices, _center) when is_list(vertices) and length(vertices) > 0 do
    count = length(vertices)

    {sum_lat, sum_lon} =
      Enum.reduce(vertices, {0.0, 0.0}, fn v, {al, ol} ->
        {al + (v["lat"] || 0.0), ol + (v["lon"] || 0.0)}
      end)

    {sum_lat / count, sum_lon / count}
  end

  defp shape_centroid(_, _), do: {0.0, 0.0}

  # Convert CSS rgba(r, g, b, a) to ARGB signed 32-bit integer string
  defp css_color_to_argb(color) when is_binary(color) do
    case Regex.run(~r/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/, color) do
      [_, r, g, b] ->
        argb_int(255, String.to_integer(r), String.to_integer(g), String.to_integer(b))

      [_, r, g, b, a] ->
        alpha = round(parse_number(a) * 255)
        argb_int(alpha, String.to_integer(r), String.to_integer(g), String.to_integer(b))

      _ ->
        # Default cyan
        "-16711681"
    end
  end

  defp css_color_to_argb(_), do: "-16711681"

  # Same as css_color_to_argb but with ~30% alpha for fill
  defp css_color_to_argb_fill(color) when is_binary(color) do
    case Regex.run(~r/rgba?\((\d+),\s*(\d+),\s*(\d+)/, color) do
      [_, r, g, b] ->
        argb_int(77, String.to_integer(r), String.to_integer(g), String.to_integer(b))

      _ ->
        # Default semi-transparent cyan
        "1291845632"
    end
  end

  defp css_color_to_argb_fill(_), do: "1291845632"

  # Parse a numeric string that may or may not have a decimal point
  defp parse_number(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp argb_int(a, r, g, b) do
    # TAK uses signed 32-bit ARGB
    value = bsl(a, 24) + bsl(r, 16) + bsl(g, 8) + b
    # Convert to signed
    signed = if value > 0x7FFFFFFF, do: value - 0x100000000, else: value
    Integer.to_string(signed)
  end

  # -- Emergency helpers --

  defp sa_event?(%{type: "a-" <> _}), do: true
  defp sa_event?(_), do: false

  defp emergency_event?(%{type: "b-a-o-" <> _}), do: true
  defp emergency_event?(_), do: false

  defp emergency_cancel?(%{type: "b-a-o-can" <> _}), do: true

  defp emergency_cancel?(%{raw_detail: raw}) when is_binary(raw) do
    String.contains?(raw, "cancel=\"true\"")
  end

  defp emergency_cancel?(_), do: false

  defp geofence_alert_event?(%{type: "b-a-g" <> _}), do: true
  defp geofence_alert_event?(_), do: false

  defp push_emergency_event(socket, event) do
    require Logger

    if emergency_cancel?(event) do
      cancel_uid = extract_emergency_client_uid(event)
      Logger.debug("DashboardChannel: cancel_emergency uid=#{cancel_uid}")
      push(socket, "cancel_emergency", %{uid: cancel_uid})
    else
      client_uid = extract_emergency_client_uid(event)
      alert = build_emergency_alert(event) |> Map.put(:uid, client_uid)
      Logger.debug("DashboardChannel: emergency_alert #{inspect(alert)}")
      push(socket, "emergency_alert", alert)
    end
  end

  defp push_sa_emergency(socket, %{raw_detail: raw} = event) when is_binary(raw) do
    if Regex.match?(@emergency_element_regex, raw) do
      if String.contains?(raw, "cancel=\"true\"") do
        push(socket, "cancel_emergency", %{uid: event.uid})
      else
        alert = build_emergency_alert(event) |> Map.put(:uid, event.uid)
        push(socket, "emergency_alert", alert)
      end
    end
  end

  defp push_sa_emergency(_socket, _event), do: :ok

  defp build_emergency_alert(event) do
    %{
      uid: event.uid,
      callsign: get_callsign(event),
      lat: event.point && event.point.lat,
      lon: event.point && event.point.lon,
      type: event.type,
      emergency_type: extract_emergency_type(event.raw_detail),
      time: format_dt(event.time),
      message: extract_remarks(event.raw_detail)
    }
  end

  defp extract_emergency_client_uid(event) do
    case event.raw_detail do
      nil ->
        event.uid

      raw ->
        case Regex.run(@emergency_link_uid_regex, raw) do
          [_, uid] -> uid
          nil -> event.uid
        end
    end
  end

  defp extract_emergency_type(nil), do: "Emergency"

  defp extract_emergency_type(raw) do
    case Regex.run(@emergency_type_regex, raw) do
      [_, type] -> type
      nil -> "Emergency"
    end
  end

  defp build_geofence_alert(event) do
    raw = event.raw_detail || ""

    trigger_uid =
      case Regex.run(@emergency_link_uid_regex, raw) do
        [_, uid] -> uid
        nil -> event.uid
      end

    geofence_ref =
      case Regex.run(@geofence_alert_ref_regex, raw) do
        [_, ref] -> ref
        nil -> nil
      end

    %{
      uid: event.uid,
      trigger_uid: trigger_uid,
      geofence_ref: geofence_ref,
      callsign: get_callsign(event),
      lat: event.point && event.point.lat,
      lon: event.point && event.point.lon,
      time: format_dt(event.time),
      remarks: extract_remarks(raw)
    }
  end

  # -- Video stream serializer --

  defp serialize_video_stream(stream) do
    hls_capable =
      stream.protocol in ["rtsp", "rtmp"] and
        ElixirTAK.Video.HLSSupervisor.available?()

    hls_url =
      if hls_capable do
        ElixirTAK.VideoRegistry.hls_url(stream.uid)
      end

    hls_status =
      if hls_capable do
        case ElixirTAK.Video.HLSWorker.status(stream.uid) do
          :not_running -> nil
          status -> to_string(status)
        end
      end

    %{
      uid: stream.uid,
      url: stream.url,
      alias: stream.alias,
      protocol: stream.protocol,
      lat: stream.lat,
      lon: stream.lon,
      hae: stream.hae,
      created_at: format_dt(stream[:created_at]),
      updated_at: format_dt(stream[:updated_at]),
      hls_url: hls_url,
      hls_status: hls_status
    }
  end
end
