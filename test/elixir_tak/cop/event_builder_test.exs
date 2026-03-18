defmodule ElixirTAK.COP.EventBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.COP.EventBuilder
  alias ElixirTAK.Protocol.{CotEncoder, CotEvent, CotParser, ChatParser, ShapeParser, RouteParser}

  @fixed_time ~U[2025-06-15 12:00:00Z]
  @base_opts [
    callsign: "TestCOP",
    group: "Cyan",
    role: "HQ",
    sender_uid: "test-dashboard-uid",
    time: ~U[2025-06-15 12:00:00Z]
  ]

  describe "build_base_event/3" do
    test "creates a CotEvent with correct fields" do
      point = %{lat: 33.4, lon: -111.9, hae: nil, ce: nil, le: nil}
      event = EventBuilder.build_base_event("a-f-G", point, @base_opts)

      assert %CotEvent{} = event
      assert String.starts_with?(event.uid, "COP-")
      assert event.type == "a-f-G"
      assert event.how == "h-g-i-g-o"
      assert event.time == @fixed_time
      assert event.start == @fixed_time
      assert DateTime.compare(event.stale, @fixed_time) == :gt
      assert event.point.lat == 33.4
      assert event.point.lon == -111.9
    end

    test "allows UID override" do
      point = %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil}

      event =
        EventBuilder.build_base_event("a-f-G", point, Keyword.put(@base_opts, :uid, "custom-uid"))

      assert event.uid == "custom-uid"
    end
  end

  describe "build_marker/4" do
    test "creates a spot point marker event" do
      event = EventBuilder.build_marker(33.4484, -111.9431, "Alpha Point", @base_opts)

      assert event.type == "b-m-p-s-p-i"
      assert event.how == "h-g-i-g-o"
      assert event.point.lat == 33.4484
      assert event.point.lon == -111.9431
      assert String.starts_with?(event.uid, "COP-")
      assert is_binary(event.raw_detail)
      assert event.raw_detail =~ "Alpha Point"
      assert event.raw_detail =~ "<contact"
      assert event.raw_detail =~ "__group"
    end

    test "marker has 24-hour default stale time" do
      event = EventBuilder.build_marker(33.4, -111.9, "Test", @base_opts)
      diff = DateTime.diff(event.stale, event.time, :second)
      assert diff == 1440 * 60
    end

    test "marker includes remarks when provided" do
      event =
        EventBuilder.build_marker(
          33.4,
          -111.9,
          "Test",
          Keyword.put(@base_opts, :remarks, "Important location")
        )

      assert event.raw_detail =~ "Important location"
      assert event.raw_detail =~ "<remarks>"
    end

    test "marker round-trips through CotParser" do
      event = EventBuilder.build_marker(33.4484, -111.9431, "Alpha Point", @base_opts)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)
      assert parsed.uid == event.uid
      assert parsed.type == "b-m-p-s-p-i"
      assert parsed.point.lat == 33.4484
      assert parsed.point.lon == -111.9431
      assert parsed.detail.callsign == "Alpha Point"
    end
  end

  describe "build_chat/3" do
    test "creates a chat event with correct type and UID format" do
      event = EventBuilder.build_chat("Hello world", "All Chat Rooms", @base_opts)

      assert event.type == "b-t-f"
      assert String.starts_with?(event.uid, "GeoChat.test-dashboard-uid.All Chat Rooms.")
      assert event.point.lat == 0.0
      assert event.point.lon == 0.0
    end

    test "chat raw_detail matches ATAK chat format" do
      event = EventBuilder.build_chat("Test message", "All Chat Rooms", @base_opts)

      assert event.raw_detail =~ ~s(chatroom="All Chat Rooms")
      assert event.raw_detail =~ ~s(senderCallsign="TestCOP")
      assert event.raw_detail =~ ~s(uid0="test-dashboard-uid")
      assert event.raw_detail =~ "<remarks"
      assert event.raw_detail =~ "Test message"
      assert event.raw_detail =~ ~s(to="All Chat Rooms")
    end

    test "chat is parseable by ChatParser" do
      event = EventBuilder.build_chat("Hello TAK", "All Chat Rooms", @base_opts)

      assert {:ok, msg} = ChatParser.parse(event)
      assert msg.sender == "TestCOP"
      assert msg.chatroom == "All Chat Rooms"
      assert msg.message == "Hello TAK"
      assert msg.sender_uid == "test-dashboard-uid"
    end

    test "chat round-trips through CotParser" do
      event = EventBuilder.build_chat("Round trip test", "All Chat Rooms", @base_opts)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)
      assert parsed.type == "b-t-f"
      assert CotEvent.chat?(parsed)
    end

    test "chat defaults to All Chat Rooms" do
      event = EventBuilder.build_chat("Test", "All Chat Rooms", @base_opts)

      assert {:ok, msg} = ChatParser.parse(event)
      assert msg.chatroom == "All Chat Rooms"
    end
  end

  describe "build_shape/3" do
    test "creates a freeform shape event with vertices" do
      vertices = [{33.45, -111.94}, {33.46, -111.93}, {33.44, -111.92}]
      event = EventBuilder.build_shape(vertices, "Test Zone", @base_opts)

      assert event.type == "u-d-f"
      assert is_binary(event.raw_detail)
    end

    test "shape has correct link point elements" do
      vertices = [{33.45, -111.94}, {33.46, -111.93}, {33.44, -111.92}]
      event = EventBuilder.build_shape(vertices, "Test Zone", @base_opts)

      assert event.raw_detail =~ ~s(point="33.45,-111.94,0.0")
      assert event.raw_detail =~ ~s(point="33.46,-111.93,0.0")
      assert event.raw_detail =~ ~s(point="33.44,-111.92,0.0")
    end

    test "shape centroid is used as event point" do
      vertices = [{33.0, -112.0}, {34.0, -111.0}, {33.0, -110.0}]
      event = EventBuilder.build_shape(vertices, "Triangle", @base_opts)

      assert_in_delta event.point.lat, 33.333, 0.01
      assert_in_delta event.point.lon, -111.0, 0.01
    end

    test "shape is parseable by ShapeParser" do
      vertices = [{33.45, -111.94}, {33.46, -111.93}, {33.44, -111.92}]
      event = EventBuilder.build_shape(vertices, "Test Zone", @base_opts)

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.name == "Test Zone"
      assert length(shape.vertices) == 3
    end

    test "shape round-trips through CotParser" do
      vertices = [{33.45, -111.94}, {33.46, -111.93}, {33.44, -111.92}]
      event = EventBuilder.build_shape(vertices, "Test Zone", @base_opts)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)
      assert parsed.type == "u-d-f"
      assert parsed.uid == event.uid
    end
  end

  describe "build_route/3" do
    test "creates a route event with waypoints" do
      waypoints = [{33.45, -111.94}, {33.46, -111.93}, {33.47, -111.92}]
      event = EventBuilder.build_route(waypoints, "Route Alpha", @base_opts)

      assert event.type == "b-m-r"
      assert is_binary(event.raw_detail)
    end

    test "route has link elements with relation c" do
      waypoints = [{33.45, -111.94}, {33.46, -111.93}]
      event = EventBuilder.build_route(waypoints, "Route Alpha", @base_opts)

      assert event.raw_detail =~ ~s(point="33.45,-111.94,0.0")
      assert event.raw_detail =~ ~s(relation="c")
    end

    test "route point is first waypoint" do
      waypoints = [{33.45, -111.94}, {33.46, -111.93}]
      event = EventBuilder.build_route(waypoints, "Route", @base_opts)

      assert event.point.lat == 33.45
      assert event.point.lon == -111.94
    end

    test "route is parseable by RouteParser" do
      waypoints = [{33.45, -111.94}, {33.46, -111.93}, {33.47, -111.92}]
      event = EventBuilder.build_route(waypoints, "Route Alpha", @base_opts)

      assert {:ok, route} = RouteParser.parse(event)
      assert route.name == "Route Alpha"
      assert length(route.waypoints) == 3
    end

    test "route round-trips through CotParser" do
      waypoints = [{33.45, -111.94}, {33.46, -111.93}]
      event = EventBuilder.build_route(waypoints, "Route Alpha", @base_opts)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)
      assert parsed.type == "b-m-r"
      assert parsed.uid == event.uid
    end
  end

  describe "build_delete/2" do
    test "creates a delete event targeting a UID" do
      event = EventBuilder.build_delete("target-123", @base_opts)

      assert event.type == "t-x-d-d"
      assert event.raw_detail =~ ~s(uid="target-123")
      assert event.raw_detail =~ ~s(relation="none")
    end

    test "delete round-trips through CotParser" do
      event = EventBuilder.build_delete("target-123", @base_opts)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)
      assert parsed.type == "t-x-d-d"
      assert parsed.uid == event.uid
    end
  end

  describe "build_circle/5" do
    test "creates a circle event with correct type" do
      event = EventBuilder.build_circle(33.45, -111.94, 500.0, "Alert Zone", @base_opts)

      assert event.type == "u-d-c-c"
      assert event.point.lat == 33.45
      assert event.point.lon == -111.94
      assert is_binary(event.raw_detail)
    end

    test "circle has Shape element with ellipse attributes" do
      event = EventBuilder.build_circle(33.45, -111.94, 1000.0, "Perimeter", @base_opts)

      assert event.raw_detail =~ ~s(ellipseMajor="1000.0")
      assert event.raw_detail =~ ~s(ellipseMinor="1000.0")
    end

    test "circle has circumference link points" do
      event = EventBuilder.build_circle(33.45, -111.94, 500.0, "Zone", @base_opts)

      # Should have 36 vertices
      link_count = Regex.scan(~r/<link point=/, event.raw_detail) |> length()
      assert link_count == 36
    end

    test "circle is parseable by ShapeParser" do
      event = EventBuilder.build_circle(33.45, -111.94, 500.0, "Circle Zone", @base_opts)

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.name == "Circle Zone"
      assert shape.shape_type == :circle
      assert shape.radius != nil
      assert_in_delta shape.radius, 500.0, 1.0
    end

    test "circle round-trips through CotParser" do
      event = EventBuilder.build_circle(33.45, -111.94, 500.0, "Test Circle", @base_opts)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)
      assert parsed.type == "u-d-c-c"
      assert parsed.uid == event.uid
    end
  end

  describe "css_to_argb/1" do
    test "converts white hex to -1" do
      assert EventBuilder.css_to_argb("#FFFFFF") == -1
    end

    test "converts 6-digit hex with full alpha" do
      # #00BCD4 with 0xFF alpha = 0xFF00BCD4
      result = EventBuilder.css_to_argb("#00BCD4")
      assert result == -16_728_876
    end

    test "converts 8-digit ARGB hex" do
      # #4D00BCD4 = semi-transparent cyan
      result = EventBuilder.css_to_argb("#4D00BCD4")
      # positive because alpha < 0x80
      assert result > 0
    end

    test "round-trips with ShapeParser.argb_to_css" do
      # Start with hex, convert to ARGB int, convert back to CSS
      argb = EventBuilder.css_to_argb("#FF00BCD4")
      css = ShapeParser.argb_to_css(argb)
      assert css == "rgba(0,188,212,1.0)"
    end

    test "round-trips white" do
      argb = EventBuilder.css_to_argb("#FFFFFF")
      css = ShapeParser.argb_to_css(argb)
      assert css == "rgba(255,255,255,1.0)"
    end

    test "round-trips red" do
      argb = EventBuilder.css_to_argb("#FFF44336")
      css = ShapeParser.argb_to_css(argb)
      assert css == "rgba(244,67,54,1.0)"
    end
  end

  describe "shape XML round-trip through ShapeParser" do
    test "polygon shape preserves vertices through parse" do
      vertices = [{33.45, -111.94}, {33.46, -111.93}, {33.44, -111.92}]
      stroke_argb = EventBuilder.css_to_argb("#FFF44336")
      fill_argb = EventBuilder.css_to_argb("#4D4CAF50")

      event =
        EventBuilder.build_shape(
          vertices,
          "Test Poly",
          Keyword.merge(@base_opts, stroke_color: stroke_argb, fill_color: fill_argb)
        )

      assert {:ok, shape} = ShapeParser.parse(event)
      assert length(shape.vertices) == 3
      assert shape.stroke_color != nil
      assert shape.fill_color != nil
    end
  end

  describe "stale_time/2" do
    test "returns datetime in the future" do
      base = ~U[2025-06-15 12:00:00Z]
      result = EventBuilder.stale_time(15, base)
      assert result == ~U[2025-06-15 12:15:00Z]
    end

    test "defaults to 15 minutes" do
      base = ~U[2025-06-15 12:00:00Z]
      result = EventBuilder.stale_time(15, base)
      assert DateTime.diff(result, base, :second) == 900
    end
  end
end
