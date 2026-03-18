defmodule ElixirTAK.Protocol.RouteParserTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, RouteParser}

  describe "parse/1" do
    test "parses route with multiple waypoints, order preserved" do
      event =
        build_route(
          "RT-1",
          "Route ALPHA",
          [
            {33.4942, -111.9261},
            {33.5100, -111.9000},
            {33.5200, -111.8800},
            {33.5050, -111.8600}
          ],
          stroke_color: "-16776961"
        )

      assert {:ok, route} = RouteParser.parse(event)
      assert route.uid == "RT-1"
      assert route.name == "Route ALPHA"
      assert route.waypoint_count == 4
      assert length(route.waypoints) == 4
      assert hd(route.waypoints) == {33.4942, -111.9261}
      assert List.last(route.waypoints) == {33.5050, -111.8600}
    end

    test "parses route name from contact callsign" do
      event =
        build_route("RT-2", "Supply Route BRAVO", [
          {33.45, -112.07},
          {33.46, -112.05}
        ])

      assert {:ok, route} = RouteParser.parse(event)
      assert route.name == "Supply Route BRAVO"
    end

    test "parses stroke color and converts ARGB to CSS" do
      event =
        build_route(
          "RT-3",
          "Test",
          [
            {33.49, -111.93},
            {33.50, -111.92}
          ],
          stroke_color: "-16776961"
        )

      assert {:ok, route} = RouteParser.parse(event)
      assert route.stroke_color == "rgba(0,0,255,1.0)"
    end

    test "parses remarks" do
      event =
        build_route(
          "RT-4",
          "Test",
          [
            {33.49, -111.93},
            {33.50, -111.92}
          ],
          remarks: "Primary supply route"
        )

      assert {:ok, route} = RouteParser.parse(event)
      assert route.remarks == "Primary supply route"
    end

    test "calculates total distance between waypoints" do
      event =
        build_route("RT-5", "Test", [
          {33.4942, -111.9261},
          {33.5100, -111.9000},
          {33.5200, -111.8800}
        ])

      assert {:ok, route} = RouteParser.parse(event)
      assert route.total_distance_m > 0
      # ~2.7km + ~2.3km = ~5km, should be in reasonable range
      assert route.total_distance_m > 3000
      assert route.total_distance_m < 8000
    end

    test "handles missing optional fields" do
      raw = """
      <detail>
        <link uid="wp1" type="b-m-p-w" relation="c" point="33.49,-111.93"/>
        <link uid="wp2" type="b-m-p-w" relation="c" point="33.50,-111.92"/>
      </detail>
      """

      event = %CotEvent{
        uid: "RT-6",
        type: "b-m-r",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: raw
      }

      assert {:ok, route} = RouteParser.parse(event)
      assert route.name == nil
      assert route.stroke_color == nil
      assert route.remarks == nil
      assert route.waypoint_count == 2
    end

    test "returns :error for non-route events" do
      event = %CotEvent{
        uid: "SA-1",
        type: "a-f-G-U-C",
        how: "m-g",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil}
      }

      assert :error = RouteParser.parse(event)
    end

    test "returns :error for nil raw_detail" do
      event = %CotEvent{
        uid: "RT-7",
        type: "b-m-r",
        how: "h-e",
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
        raw_detail: nil
      }

      assert :error = RouteParser.parse(event)
    end

    test "single waypoint results in zero distance" do
      event = build_route("RT-8", "Short", [{33.49, -111.93}])

      assert {:ok, route} = RouteParser.parse(event)
      assert route.waypoint_count == 1
      assert route.total_distance_m == 0.0
    end

    test "filters only relation=c links, ignores other links" do
      raw = """
      <detail>
        <contact callsign="Test Route"/>
        <link uid="ref1" type="a-f-G" relation="p-p" point="33.40,-111.90"/>
        <link uid="wp1" type="b-m-p-w" relation="c" point="33.49,-111.93"/>
        <link uid="wp2" type="b-m-p-w" relation="c" point="33.50,-111.92"/>
      </detail>
      """

      event = %CotEvent{
        uid: "RT-9",
        type: "b-m-r",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: raw
      }

      assert {:ok, route} = RouteParser.parse(event)
      assert route.waypoint_count == 2
      assert route.waypoints == [{33.49, -111.93}, {33.50, -111.92}]
    end

    test "handles point before relation in link attributes" do
      raw = """
      <detail>
        <link uid="wp1" type="b-m-p-w" point="33.49,-111.93" relation="c"/>
        <link uid="wp2" point="33.50,-111.92" type="b-m-p-w" relation="c"/>
      </detail>
      """

      event = %CotEvent{
        uid: "RT-10",
        type: "b-m-r",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: raw
      }

      assert {:ok, route} = RouteParser.parse(event)
      assert route.waypoint_count == 2
    end

    test "empty links results in zero waypoints" do
      raw = """
      <detail>
        <contact callsign="Empty Route"/>
      </detail>
      """

      event = %CotEvent{
        uid: "RT-11",
        type: "b-m-r",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: raw
      }

      assert {:ok, route} = RouteParser.parse(event)
      assert route.waypoint_count == 0
      assert route.waypoints == []
    end

    test "handles malformed point strings" do
      raw = """
      <detail>
        <link uid="wp1" type="b-m-p-w" relation="c" point="bad"/>
        <link uid="wp2" type="b-m-p-w" relation="c" point="33.50,-111.92"/>
      </detail>
      """

      event = %CotEvent{
        uid: "RT-12",
        type: "b-m-r",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: raw
      }

      assert {:ok, route} = RouteParser.parse(event)
      # Only the valid waypoint should be parsed
      assert route.waypoint_count == 1
    end
  end

  describe "parse!/1" do
    test "returns route map on success" do
      event = build_route("RT-20", "Zone", [{33.49, -111.93}, {33.50, -111.92}])
      assert %{uid: "RT-20"} = RouteParser.parse!(event)
    end

    test "returns nil on failure" do
      event = %CotEvent{
        uid: "SA-1",
        type: "a-f-G-U-C",
        how: "m-g",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil}
      }

      assert nil == RouteParser.parse!(event)
    end
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_route(uid, name, waypoints, opts \\ []) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)

    link_elements =
      waypoints
      |> Enum.with_index()
      |> Enum.map(fn {{lat, lon}, i} ->
        ~s(<link uid="wp#{i}" type="b-m-p-w" relation="c" point="#{lat},#{lon}"/>)
      end)
      |> Enum.join("\n    ")

    color_elements =
      [
        if(opts[:stroke_color], do: ~s(<strokeColor value="#{opts[:stroke_color]}"/>)),
        if(opts[:remarks], do: ~s(<remarks>#{opts[:remarks]}</remarks>))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n    ")

    contact = if name, do: ~s(<contact callsign="#{name}"/>), else: ""

    raw = """
    <detail>
      #{contact}
      #{link_elements}
      #{color_elements}
    </detail>
    """

    %CotEvent{
      uid: uid,
      type: "b-m-r",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: name, group: nil, track: nil},
      raw_detail: raw
    }
  end
end
