defmodule ElixirTAK.Protocol.GeofenceParserTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, GeofenceParser}

  describe "geofence_event?/1" do
    test "returns true for u-d-* event with __geofence element" do
      event = build_geofence_event("GF-1", "Zone Alpha", "Entry")
      assert GeofenceParser.geofence_event?(event)
    end

    test "returns false for u-d-* event without __geofence element" do
      event = build_plain_shape("SHP-1")
      refute GeofenceParser.geofence_event?(event)
    end

    test "returns false for non u-d-* event" do
      event = %CotEvent{
        uid: "SA-1",
        type: "a-f-G-U-C",
        how: "m-g",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil}
      }

      refute GeofenceParser.geofence_event?(event)
    end

    test "returns false for nil raw_detail" do
      event = %CotEvent{
        uid: "GF-2",
        type: "u-d-p",
        how: "h-e",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil},
        raw_detail: nil
      }

      refute GeofenceParser.geofence_event?(event)
    end
  end

  describe "parse/1" do
    test "parses a geofence with all attributes" do
      event =
        build_geofence_event("GF-1", "Restricted Zone", "Entry",
          monitor_type: "TAKUsers",
          boundary_type: "Inclusive",
          min_elevation: "0.0",
          max_elevation: "1000.0"
        )

      assert {:ok, geofence} = GeofenceParser.parse(event)
      assert geofence.uid == "GF-1"
      assert geofence.name == "Restricted Zone"
      assert geofence.trigger == "Entry"
      assert geofence.monitor_type == "TAKUsers"
      assert geofence.boundary_type == "Inclusive"
      assert geofence.min_elevation == 0.0
      assert geofence.max_elevation == 1000.0
      assert geofence.shape_type == :polygon
      assert length(geofence.vertices) == 4
    end

    test "parses geofence with minimal attributes" do
      event = build_geofence_event("GF-2", "Zone B", "Exit")

      assert {:ok, geofence} = GeofenceParser.parse(event)
      assert geofence.trigger == "Exit"
      assert geofence.monitor_type == nil
      assert geofence.boundary_type == nil
      assert geofence.min_elevation == nil
      assert geofence.max_elevation == nil
    end

    test "parses Both trigger type" do
      event = build_geofence_event("GF-3", "Zone C", "Both")

      assert {:ok, geofence} = GeofenceParser.parse(event)
      assert geofence.trigger == "Both"
    end

    test "includes shape fields from ShapeParser" do
      event =
        build_geofence_event("GF-4", "Colored Zone", "Entry",
          stroke_color: "-1",
          fill_color: "1375731712"
        )

      assert {:ok, geofence} = GeofenceParser.parse(event)
      assert geofence.stroke_color != nil
      assert geofence.fill_color != nil
      assert geofence.remarks == "Geofence area"
    end

    test "returns :error for plain shape without __geofence" do
      event = build_plain_shape("SHP-1")
      assert :error = GeofenceParser.parse(event)
    end

    test "returns :error for non-shape event" do
      event = %CotEvent{
        uid: "SA-1",
        type: "a-f-G-U-C",
        how: "m-g",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil}
      }

      assert :error = GeofenceParser.parse(event)
    end

    test "returns :error for nil raw_detail" do
      event = %CotEvent{
        uid: "GF-5",
        type: "u-d-p",
        how: "h-e",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil},
        raw_detail: nil
      }

      assert :error = GeofenceParser.parse(event)
    end
  end

  describe "parse!/1" do
    test "returns geofence map on success" do
      event = build_geofence_event("GF-6", "Zone D", "Entry")
      assert %{uid: "GF-6", trigger: "Entry"} = GeofenceParser.parse!(event)
    end

    test "returns nil on failure" do
      event = build_plain_shape("SHP-2")
      assert nil == GeofenceParser.parse!(event)
    end
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_geofence_event(uid, name, trigger, opts \\ []) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)

    monitor = if opts[:monitor_type], do: ~s( monitorType="#{opts[:monitor_type]}"), else: ""
    boundary = if opts[:boundary_type], do: ~s( boundaryType="#{opts[:boundary_type]}"), else: ""
    min_elev = if opts[:min_elevation], do: ~s( minElevation="#{opts[:min_elevation]}"), else: ""
    max_elev = if opts[:max_elevation], do: ~s( maxElevation="#{opts[:max_elevation]}"), else: ""

    stroke =
      if opts[:stroke_color],
        do: ~s(\n    <strokeColor value="#{opts[:stroke_color]}"/>),
        else: ""

    fill = if opts[:fill_color], do: ~s(\n    <fillColor value="#{opts[:fill_color]}"/>), else: ""

    raw = """
    <detail>
      <contact callsign="#{name}"/>
      <link point="33.49,-111.93"/>
      <link point="33.50,-111.93"/>
      <link point="33.50,-111.94"/>
      <link point="33.49,-111.94"/>
      <__geofence trigger="#{trigger}"#{monitor}#{boundary}#{min_elev}#{max_elev}/>#{stroke}#{fill}
      <remarks>Geofence area</remarks>
    </detail>
    """

    %CotEvent{
      uid: uid,
      type: "u-d-p",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 33.495, lon: -111.935, hae: nil, ce: nil, le: nil},
      detail: %{callsign: name, group: nil, track: nil},
      raw_detail: raw
    }
  end

  defp build_plain_shape(uid) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)

    raw = """
    <detail>
      <contact callsign="Plain Shape"/>
      <link point="33.49,-111.93"/>
      <link point="33.50,-111.93"/>
      <link point="33.50,-111.94"/>
    </detail>
    """

    %CotEvent{
      uid: uid,
      type: "u-d-p",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil},
      detail: %{callsign: "Plain Shape", group: nil, track: nil},
      raw_detail: raw
    }
  end
end
