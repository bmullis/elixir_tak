defmodule ElixirTAK.Protocol.ShapeParserTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, ShapeParser}

  describe "parse/1" do
    test "parses a polygon with vertices and colors" do
      event =
        build_shape(
          "SHP-1",
          "u-d-p",
          "Patrol Zone",
          [
            {33.49, -111.93},
            {33.50, -111.93},
            {33.50, -111.94},
            {33.49, -111.94}
          ],
          stroke_color: -1,
          fill_color: 1_375_731_712
        )

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.uid == "SHP-1"
      assert shape.name == "Patrol Zone"
      assert shape.shape_type == :polygon
      assert length(shape.vertices) == 4
      assert hd(shape.vertices) == {33.49, -111.93}
      assert shape.stroke_color != nil
      assert shape.fill_color != nil
      assert shape.center == nil
      assert shape.radius == nil
    end

    test "parses a rectangle as 4-vertex polygon" do
      event =
        build_shape("SHP-2", "u-d-r", "LZ Alpha", [
          {33.49, -111.93},
          {33.49, -111.92},
          {33.48, -111.92},
          {33.48, -111.93}
        ])

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.shape_type == :rectangle
      assert length(shape.vertices) == 4
    end

    test "parses a freeform drawing" do
      event =
        build_shape("SHP-3", "u-d-f", "Route Mark", [
          {33.49, -111.93},
          {33.495, -111.935},
          {33.50, -111.94}
        ])

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.shape_type == :freeform
      assert length(shape.vertices) == 3
    end

    test "parses a circle with ellipse attributes" do
      raw = """
      <detail>
        <contact callsign="Danger Zone"/>
        <Shape ellipseMajor="500.0" ellipseMinor="500.0"/>
        <strokeColor value="-16776961"/>
        <fillColor value="536870912"/>
        <remarks>Keep out</remarks>
      </detail>
      """

      event = %CotEvent{
        uid: "SHP-4",
        type: "u-d-c-c",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil},
        detail: %{callsign: "Danger Zone", group: nil, track: nil},
        raw_detail: raw
      }

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.shape_type == :circle
      assert shape.name == "Danger Zone"
      assert shape.center == {33.49, -111.93}
      assert shape.radius == 500.0
      assert shape.remarks == "Keep out"
    end

    test "parses circle with vertices as fallback radius" do
      event =
        build_shape("SHP-5", "u-d-c-c", "Area", [{33.50, -111.93}], center: {33.49, -111.93})

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.shape_type == :circle
      assert shape.radius != nil
      assert shape.radius > 0
    end

    test "extracts remarks" do
      event =
        build_shape(
          "SHP-6",
          "u-d-p",
          "Test",
          [{33.49, -111.93}, {33.50, -111.94}, {33.51, -111.93}],
          remarks: "Important area"
        )

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.remarks == "Important area"
    end

    test "handles missing name gracefully" do
      raw = """
      <detail>
        <link point="33.49,-111.93"/>
        <link point="33.50,-111.94"/>
        <link point="33.51,-111.93"/>
      </detail>
      """

      event = %CotEvent{
        uid: "SHP-7",
        type: "u-d-p",
        how: "h-e",
        time: DateTime.utc_now(),
        start: DateTime.utc_now(),
        stale: DateTime.add(DateTime.utc_now(), 86_400, :second),
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: raw
      }

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.name == nil
      assert length(shape.vertices) == 3
    end

    test "handles missing colors gracefully" do
      event =
        build_shape("SHP-8", "u-d-p", "Plain", [
          {33.49, -111.93},
          {33.50, -111.94},
          {33.51, -111.93}
        ])

      assert {:ok, shape} = ShapeParser.parse(event)
      assert shape.stroke_color == nil
      assert shape.fill_color == nil
    end

    test "returns :error for non-shape event" do
      event = %CotEvent{
        uid: "SA-1",
        type: "a-f-G-U-C",
        how: "m-g",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil}
      }

      assert :error = ShapeParser.parse(event)
    end

    test "returns :error for nil raw_detail" do
      event = %CotEvent{
        uid: "SHP-9",
        type: "u-d-p",
        how: "h-e",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil},
        raw_detail: nil
      }

      assert :error = ShapeParser.parse(event)
    end
  end

  describe "parse!/1" do
    test "returns shape map on success" do
      event =
        build_shape("SHP-10", "u-d-p", "Zone", [
          {33.49, -111.93},
          {33.50, -111.94},
          {33.51, -111.93}
        ])

      assert %{uid: "SHP-10"} = ShapeParser.parse!(event)
    end

    test "returns nil on failure" do
      event = %CotEvent{
        uid: "SA-1",
        type: "a-f-G-U-C",
        how: "m-g",
        point: %{lat: 33.49, lon: -111.93, hae: nil, ce: nil, le: nil}
      }

      assert nil == ShapeParser.parse!(event)
    end
  end

  describe "argb_to_css/1" do
    test "converts white (fully opaque)" do
      # 0xFFFFFFFF as signed = -1
      assert "rgba(255,255,255,1.0)" = ShapeParser.argb_to_css(-1)
    end

    test "converts red with full alpha" do
      # 0xFFFF0000 as signed = -65536
      assert "rgba(255,0,0,1.0)" = ShapeParser.argb_to_css(-65_536)
    end

    test "converts blue with full alpha" do
      # 0xFF0000FF as signed = -16776961
      assert "rgba(0,0,255,1.0)" = ShapeParser.argb_to_css(-16_776_961)
    end

    test "converts semi-transparent green" do
      # 0x8000FF00: A=128, R=0, G=255, B=0
      assert "rgba(0,255,0,0.5)" = ShapeParser.argb_to_css(-2_147_418_368)
    end

    test "converts zero (transparent black)" do
      assert "rgba(0,0,0,0.0)" = ShapeParser.argb_to_css(0)
    end
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_shape(uid, type, name, vertices, opts \\ []) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 86_400, :second)
    {center_lat, center_lon} = Keyword.get(opts, :center, {33.49, -111.93})

    link_elements =
      Enum.map(vertices, fn {lat, lon} ->
        ~s(<link point="#{lat},#{lon}"/>)
      end)
      |> Enum.join("\n    ")

    color_elements =
      [
        if(opts[:stroke_color], do: ~s(<strokeColor value="#{opts[:stroke_color]}"/>)),
        if(opts[:fill_color], do: ~s(<fillColor value="#{opts[:fill_color]}"/>)),
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
      type: type,
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: center_lat, lon: center_lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: name, group: nil, track: nil},
      raw_detail: raw
    }
  end
end
