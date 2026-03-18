defmodule ElixirTAK.Dev.Simulator do
  @moduledoc """
  Simulates TAK clients for dashboard development and testing.

  Spawns 9 fake clients around Scottsdale, AZ with different movement patterns
  and mixed affiliations (friendly, hostile, neutral, unknown).
  Directly populates SACache/ClientRegistry and broadcasts on PubSub, bypassing
  TCP entirely. Auto-starts in dev when `config :elixir_tak, simulator: true`.
  """

  use GenServer

  alias ElixirTAK.Protocol.CotEvent

  alias ElixirTAK.{
    ChatCache,
    ClientRegistry,
    GeofenceCache,
    History,
    MarkerCache,
    Metrics,
    RouteCache,
    SACache
  }

  @pubsub ElixirTAK.PubSub
  @cot_topic "cot:broadcast"
  @update_ms 3_000
  @chat_min_ms 15_000
  @chat_max_ms 30_000
  @emergency_min_ms 60_000
  @emergency_max_ms 90_000
  @emergency_duration_ms 15_000

  @clients [
    # Friendly forces
    %{
      uid: "SIM-ALPHA-01",
      callsign: "ALPHA-1",
      type: "a-f-G-U-C",
      group: "Cyan",
      base_lat: 33.4942,
      base_lon: -111.9261,
      pattern: :patrol
    },
    %{
      uid: "SIM-BRAVO-02",
      callsign: "BRAVO-2",
      type: "a-f-G-U-C",
      group: "Cyan",
      base_lat: 33.4484,
      base_lon: -112.0740,
      pattern: :wander
    },
    %{
      uid: "SIM-CHARLIE-03",
      callsign: "CHARLIE-3",
      type: "a-f-G-U-C",
      group: "Yellow",
      base_lat: 33.5000,
      base_lon: -112.0000,
      pattern: :circle
    },
    %{
      uid: "SIM-DELTA-04",
      callsign: "DELTA-4",
      type: "a-f-G-U-C",
      group: "Yellow",
      base_lat: 33.4200,
      base_lon: -111.9500,
      pattern: :waypoint
    },
    %{
      uid: "SIM-ECHO-05",
      callsign: "ECHO-5",
      type: "a-f-G-U-C",
      group: "Magenta",
      base_lat: 33.4700,
      base_lon: -111.9800,
      pattern: :stationary
    },
    %{
      uid: "SIM-FOXTROT-06",
      callsign: "FOXTROT-6",
      type: "a-f-G-U-C",
      group: "Cyan",
      base_lat: 33.4600,
      base_lon: -112.0300,
      pattern: :wander
    },
    # Hostile
    %{
      uid: "SIM-GHOST-07",
      callsign: "GHOST-7",
      type: "a-h-G-U-C",
      group: "Red",
      base_lat: 33.4850,
      base_lon: -111.9400,
      pattern: :patrol
    },
    # Neutral
    %{
      uid: "SIM-NOMAD-08",
      callsign: "NOMAD-8",
      type: "a-n-G-U-C",
      group: "Green",
      base_lat: 33.4550,
      base_lon: -111.9650,
      pattern: :wander
    },
    # Unknown
    %{
      uid: "SIM-SPECTER-09",
      callsign: "SPECTER-9",
      type: "a-u-G-U-C",
      group: "Yellow",
      base_lat: 33.4750,
      base_lon: -112.0100,
      pattern: :circle
    }
  ]

  @markers [
    %{
      uid: "SIM-MKR-CP1",
      callsign: "Checkpoint Alpha",
      remarks: "Primary entry control point",
      lat: 33.4900,
      lon: -111.9200
    },
    %{
      uid: "SIM-MKR-OP1",
      callsign: "OP North",
      remarks: "Observation post, overwatch on Route 101",
      lat: 33.5050,
      lon: -111.9350
    },
    %{
      uid: "SIM-MKR-LZ1",
      callsign: "LZ Hawk",
      remarks: "Landing zone, cleared and marked",
      lat: 33.4650,
      lon: -111.9550
    },
    %{
      uid: "SIM-MKR-SUP1",
      callsign: "Supply Cache",
      remarks: "Water and ammo resupply point",
      lat: 33.4780,
      lon: -112.0050
    }
  ]

  @routes [
    %{
      uid: "SIM-ROUTE-01",
      name: "Route ALPHA",
      waypoints: [
        {33.4942, -111.9261},
        {33.5000, -111.9100},
        {33.5100, -111.9000},
        {33.5200, -111.8800}
      ],
      color: "-16776961"
    },
    %{
      uid: "SIM-ROUTE-02",
      name: "Supply Route BRAVO",
      waypoints: [
        {33.4484, -112.0740},
        {33.4600, -112.0500},
        {33.4700, -112.0200},
        {33.4800, -111.9900},
        {33.4900, -111.9600}
      ],
      color: "-256"
    }
  ]

  @geofences [
    %{
      uid: "SIM-FENCE-01",
      name: "Old Town Restricted",
      trigger: "Entry",
      vertices: [
        {33.4945, -111.9265},
        {33.4945, -111.9215},
        {33.4905, -111.9215},
        {33.4905, -111.9265}
      ],
      color: "-32768"
    },
    %{
      uid: "SIM-FENCE-02",
      name: "Airfield Perimeter",
      trigger: "Both",
      vertices: [
        {33.4680, -111.9600},
        {33.4680, -111.9520},
        {33.4630, -111.9520},
        {33.4630, -111.9600}
      ],
      color: "-23296"
    }
  ]

  @chat_messages [
    "Moving to checkpoint",
    "All clear at this position",
    "Roger that, copy",
    "Eyes on target area",
    "Requesting update",
    "Holding position",
    "Proceeding to next waypoint",
    "Comms check, how copy?",
    "Solid copy, standing by",
    "Be advised, area is secure"
  ]

  # -- Public API ------------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def stop, do: GenServer.stop(__MODULE__)
  def running?, do: Process.whereis(__MODULE__) != nil

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_opts) do
    clients =
      Enum.map(@clients, fn client ->
        ClientRegistry.register(client.uid, %{
          callsign: client.callsign,
          group: client.group,
          peer: {{127, 0, 0, 1}, 0},
          cert_cn: "SIM:#{client.callsign}"
        })

        init_client(client)
      end)

    # Seed initial positions
    Enum.each(clients, &emit_position/1)

    # Place markers, routes, and geofences once
    Enum.each(@markers, &emit_marker/1)
    Enum.each(@routes, &emit_route/1)
    Enum.each(@geofences, &emit_geofence/1)

    schedule_tick()
    schedule_chat()
    schedule_emergency()

    {:ok, %{clients: clients}}
  end

  @impl true
  def handle_info(:tick, state) do
    clients =
      Enum.map(state.clients, fn client ->
        client = move(client)
        emit_position(client)
        client
      end)

    schedule_tick()
    {:noreply, %{state | clients: clients}}
  end

  def handle_info(:chat, state) do
    client = Enum.random(state.clients)
    emit_chat(client)
    schedule_chat()
    {:noreply, state}
  end

  def handle_info(:emergency, state) do
    client = Enum.random(state.clients)
    emit_emergency(client)
    Process.send_after(self(), {:cancel_emergency, client.uid}, @emergency_duration_ms)
    schedule_emergency()
    {:noreply, state}
  end

  def handle_info({:cancel_emergency, uid}, state) do
    client = Enum.find(state.clients, &(&1.uid == uid))
    if client, do: emit_emergency_cancel(client)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.clients, fn c ->
      SACache.delete(c.uid)
      ClientRegistry.unregister(c.uid)
    end)

    :ok
  end

  # -- Movement patterns -----------------------------------------------------

  defp init_client(client) do
    offset_lat = (:rand.uniform() - 0.5) * 0.01
    offset_lon = (:rand.uniform() - 0.5) * 0.01

    Map.merge(client, %{
      lat: client.base_lat + offset_lat,
      lon: client.base_lon + offset_lon,
      speed: 0.0,
      course: :rand.uniform() * 360.0,
      tick: 0,
      patrol_dir: 1
    })
  end

  defp move(%{pattern: :stationary} = c) do
    # Small jitter around current position
    %{
      c
      | lat: c.lat + (:rand.uniform() - 0.5) * 0.0001,
        lon: c.lon + (:rand.uniform() - 0.5) * 0.0001,
        speed: 0.0,
        tick: c.tick + 1
    }
  end

  defp move(%{pattern: :patrol} = c) do
    # Linear back-and-forth along a bearing
    step = 0.0003 * c.patrol_dir
    new_lat = c.lat + step * :math.cos(c.course * :math.pi() / 180)
    new_lon = c.lon + step * :math.sin(c.course * :math.pi() / 180)

    # Reverse direction every 20 ticks
    patrol_dir = if rem(c.tick + 1, 20) == 0, do: -c.patrol_dir, else: c.patrol_dir

    course =
      if patrol_dir != c.patrol_dir,
        do: Float.round(:math.fmod(c.course + 180, 360), 1),
        else: c.course

    %{
      c
      | lat: new_lat,
        lon: new_lon,
        speed: 2.5,
        course: course,
        tick: c.tick + 1,
        patrol_dir: patrol_dir
    }
  end

  defp move(%{pattern: :circle} = c) do
    # Orbit around base point
    radius = 0.005
    angle = c.tick * 0.15
    new_lat = c.base_lat + radius * :math.cos(angle)
    new_lon = c.base_lon + radius * :math.sin(angle)
    course = Float.round(:math.fmod(angle * 180 / :math.pi() + 90, 360.0), 1)

    %{c | lat: new_lat, lon: new_lon, speed: 5.0, course: abs(course), tick: c.tick + 1}
  end

  defp move(%{pattern: :waypoint} = c) do
    waypoints = [
      {c.base_lat, c.base_lon},
      {c.base_lat + 0.008, c.base_lon + 0.005},
      {c.base_lat + 0.003, c.base_lon - 0.008},
      {c.base_lat - 0.005, c.base_lon + 0.003}
    ]

    wp_index = rem(div(c.tick, 10), length(waypoints))
    {target_lat, target_lon} = Enum.at(waypoints, wp_index)

    # Move toward target waypoint
    dlat = (target_lat - c.lat) * 0.15
    dlon = (target_lon - c.lon) * 0.15
    course = :math.atan2(dlon, dlat) * 180 / :math.pi()

    %{
      c
      | lat: c.lat + dlat,
        lon: c.lon + dlon,
        speed: 8.0,
        course: Float.round(:math.fmod(course + 360, 360.0), 1),
        tick: c.tick + 1
    }
  end

  defp move(%{pattern: :wander} = c) do
    # Random walk with smoothed heading changes
    course_delta = (:rand.uniform() - 0.5) * 30
    new_course = :math.fmod(c.course + course_delta + 360, 360.0)
    step = 0.0002

    new_lat = c.lat + step * :math.cos(new_course * :math.pi() / 180)
    new_lon = c.lon + step * :math.sin(new_course * :math.pi() / 180)

    %{
      c
      | lat: new_lat,
        lon: new_lon,
        speed: 1.5,
        course: Float.round(new_course, 1),
        tick: c.tick + 1
    }
  end

  # -- Event emission --------------------------------------------------------

  defp emit_position(client) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    event = %CotEvent{
      uid: client.uid,
      type: client.type,
      how: "m-g",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: client.lat, lon: client.lon, hae: 0.0, ce: 9_999_999.0, le: 9_999_999.0},
      detail: %{
        callsign: client.callsign,
        group: %{name: client.group, role: "Team Member"},
        track: %{speed: client.speed, course: client.course}
      }
    }

    SACache.put(event, client.group)
    Metrics.record_event(event.type)
    History.Writer.record(event, nil, client.group)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, client.uid, event, client.group}
    )
  end

  defp emit_chat(client) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 120, :second)
    message = Enum.random(@chat_messages)
    chatroom = "All Chat Rooms"

    chat_uid =
      "GeoChat.#{client.uid}.#{chatroom}.#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

    raw_detail = """
    <detail>\
    <__chat parent="RootContactGroup" groupOwner="false" \
    chatroom="#{chatroom}" id="#{chatroom}" \
    senderCallsign="#{client.callsign}">\
    <chatgrp uid0="#{client.uid}" uid1="#{chatroom}" id="#{chatroom}"/>\
    </__chat>\
    <link uid="#{client.uid}" type="#{client.type}" relation="p-p"/>\
    <remarks source="BAO.F.ATAK.#{client.uid}" sourceID="#{client.uid}" \
    to="#{chatroom}" time="#{DateTime.to_iso8601(now)}">#{message}</remarks>\
    </detail>\
    """

    event = %CotEvent{
      uid: chat_uid,
      type: "b-t-f",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: nil, group: nil, track: nil},
      raw_detail: raw_detail
    }

    ChatCache.put(event)
    Metrics.record_event(event.type)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, client.uid, event, client.group}
    )
  end

  defp emit_marker(marker) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)

    raw_detail = """
    <detail>\
    <contact callsign="#{marker.callsign}"/>\
    <remarks>#{marker.remarks}</remarks>\
    </detail>\
    """

    event = %CotEvent{
      uid: marker.uid,
      type: "b-m-p-s-p-i",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: marker.lat, lon: marker.lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: marker.callsign, group: nil, track: nil},
      raw_detail: raw_detail
    }

    MarkerCache.put(event)
    Metrics.record_event(event.type)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, marker.uid, event, nil}
    )
  end

  defp emit_route(route) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)

    links =
      route.waypoints
      |> Enum.with_index()
      |> Enum.map(fn {{lat, lon}, i} ->
        ~s(<link uid="#{route.uid}-wp#{i}" type="b-m-p-w" relation="c" point="#{lat},#{lon}"/>)
      end)
      |> Enum.join("\n    ")

    raw_detail = """
    <detail>\
    <contact callsign="#{route.name}"/>\
    #{links}\
    <strokeColor value="#{route.color}"/>\
    <remarks>Simulated route</remarks>\
    </detail>\
    """

    event = %CotEvent{
      uid: route.uid,
      type: "b-m-r",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: route.name, group: nil, track: nil},
      raw_detail: raw_detail
    }

    RouteCache.put(event)
    Metrics.record_event(event.type)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, route.uid, event, nil}
    )
  end

  defp emit_geofence(fence) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)

    links =
      fence.vertices
      |> Enum.with_index()
      |> Enum.map(fn {{lat, lon}, i} ->
        ~s(<link uid="#{fence.uid}-v#{i}" type="b-m-p-w" relation="c" point="#{lat},#{lon}"/>)
      end)
      |> Enum.join("\n    ")

    raw_detail = """
    <detail>\
    <contact callsign="#{fence.name}"/>\
    #{links}\
    <__geofence trigger="#{fence.trigger}" monitorType="TAKUsers" boundaryType="Inclusive"/>\
    <strokeColor value="#{fence.color}"/>\
    <fillColor value="#{fence.color}"/>\
    <remarks>Simulated geofence</remarks>\
    </detail>\
    """

    {center_lat, center_lon} = fence_center(fence.vertices)

    event = %CotEvent{
      uid: fence.uid,
      type: "u-d-p",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: center_lat, lon: center_lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: fence.name, group: nil, track: nil},
      raw_detail: raw_detail
    }

    GeofenceCache.put(event)
    Metrics.record_event(event.type)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, fence.uid, event, nil}
    )
  end

  defp fence_center(vertices) do
    count = length(vertices)

    {sum_lat, sum_lon} =
      Enum.reduce(vertices, {0.0, 0.0}, fn {lat, lon}, {al, ol} -> {al + lat, ol + lon} end)

    {sum_lat / count, sum_lon / count}
  end

  defp emit_emergency(client) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 1800, :second)

    raw_detail = """
    <detail>\
    <contact callsign="#{client.callsign}"/>\
    <emergency type="911 Alert">#{client.callsign}</emergency>\
    <link uid="#{client.uid}" type="#{client.type}" relation="p-p"/>\
    <remarks>Emergency beacon activated</remarks>\
    </detail>\
    """

    event = %CotEvent{
      uid: client.uid,
      type: "b-a-o-tbl",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: client.lat, lon: client.lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: client.callsign, group: nil, track: nil},
      raw_detail: raw_detail
    }

    Metrics.record_event(event.type)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, client.uid, event, client.group}
    )
  end

  defp emit_emergency_cancel(client) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    raw_detail = """
    <detail>\
    <contact callsign="#{client.callsign}"/>\
    <emergency cancel="true">#{client.callsign}</emergency>\
    </detail>\
    """

    event = %CotEvent{
      uid: client.uid,
      type: "b-a-o-can",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: client.lat, lon: client.lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: client.callsign, group: nil, track: nil},
      raw_detail: raw_detail
    }

    Metrics.record_event(event.type)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, client.uid, event, client.group}
    )
  end

  # -- Scheduling ------------------------------------------------------------

  defp schedule_tick do
    Process.send_after(self(), :tick, @update_ms)
  end

  defp schedule_chat do
    delay = @chat_min_ms + :rand.uniform(@chat_max_ms - @chat_min_ms)
    Process.send_after(self(), :chat, delay)
  end

  defp schedule_emergency do
    delay = @emergency_min_ms + :rand.uniform(@emergency_max_ms - @emergency_min_ms)
    Process.send_after(self(), :emergency, delay)
  end
end
