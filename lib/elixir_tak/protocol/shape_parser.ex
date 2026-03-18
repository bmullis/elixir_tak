defmodule ElixirTAK.Protocol.ShapeParser do
  @moduledoc """
  Extracts structured shape data from a CotEvent's raw_detail XML.

  Shape events (type `u-d-*`) carry vertices, colors, and metadata inside
  `<detail>`. This module parses those fields into a map suitable for
  rendering on the CesiumJS map.

  ## TAK shape types

  - `u-d-p` - polygon
  - `u-d-r` - rectangle (4-vertex polygon)
  - `u-d-f` - freeform drawing
  - `u-d-c-c` - circle (center + radius)

  ## Color format

  TAK uses signed 32-bit ARGB integers for stroke and fill colors.
  This module converts them to `rgba(R,G,B,A)` CSS strings.
  """

  alias ElixirTAK.Protocol.CotEvent

  @type shape :: %{
          uid: String.t(),
          name: String.t() | nil,
          shape_type: :polygon | :rectangle | :circle | :freeform,
          vertices: [{float(), float()}],
          stroke_color: String.t() | nil,
          fill_color: String.t() | nil,
          remarks: String.t() | nil,
          center: {float(), float()} | nil,
          radius: float() | nil
        }

  @doc """
  Parse a shape CotEvent into a structured shape map.

  Returns `{:ok, shape}` or `:error`.
  """
  @spec parse(%CotEvent{}) :: {:ok, shape()} | :error
  def parse(%CotEvent{type: "u-d-" <> _ = type, raw_detail: raw} = event)
      when is_binary(raw) do
    shape_type = classify_type(type)
    vertices = extract_vertices(raw)
    name = extract_name(raw)

    shape = %{
      uid: event.uid,
      name: name,
      shape_type: shape_type,
      vertices: vertices,
      stroke_color: extract_color(raw, "strokeColor"),
      fill_color: extract_color(raw, "fillColor"),
      remarks: extract_remarks(raw)
    }

    shape =
      if shape_type == :circle do
        center = {event.point.lat, event.point.lon}
        radius = extract_circle_radius(raw, vertices, center)
        Map.merge(shape, %{center: center, radius: radius})
      else
        Map.merge(shape, %{center: nil, radius: nil})
      end

    {:ok, shape}
  end

  def parse(_), do: :error

  @doc """
  Like `parse/1` but returns the map directly or nil.
  """
  @spec parse!(%CotEvent{}) :: shape() | nil
  def parse!(%CotEvent{} = event) do
    case parse(event) do
      {:ok, shape} -> shape
      :error -> nil
    end
  end

  @doc """
  Convert a TAK ARGB signed 32-bit integer to a CSS rgba() string.

  TAK stores colors as signed Java integers. The format is ARGB:
  bits 31-24 = alpha, 23-16 = red, 15-8 = green, 7-0 = blue.
  """
  @spec argb_to_css(integer()) :: String.t()
  def argb_to_css(value) when is_integer(value) do
    # Convert signed to unsigned 32-bit
    unsigned = value |> Bitwise.band(0xFFFFFFFF)
    a = unsigned |> Bitwise.bsr(24) |> Bitwise.band(0xFF)
    r = unsigned |> Bitwise.bsr(16) |> Bitwise.band(0xFF)
    g = unsigned |> Bitwise.bsr(8) |> Bitwise.band(0xFF)
    b = unsigned |> Bitwise.band(0xFF)
    alpha = Float.round(a / 255, 2)
    "rgba(#{r},#{g},#{b},#{alpha})"
  end

  # -- Private ---------------------------------------------------------------

  defp classify_type("u-d-r" <> _), do: :rectangle
  defp classify_type("u-d-c-c" <> _), do: :circle
  defp classify_type("u-d-f" <> _), do: :freeform
  defp classify_type("u-d-p" <> _), do: :polygon
  defp classify_type("u-d-" <> _), do: :polygon

  @vertex_regex ~r{<link\s[^>]*point="([^"]+)"[^>]*/>}
  @name_regex ~r/<contact\s[^>]*callsign="([^"]+)"/
  @remarks_regex ~r/<remarks[^>]*>(.*?)<\/remarks>/s

  defp extract_vertices(raw) do
    Regex.scan(@vertex_regex, raw)
    |> Enum.flat_map(fn
      [_, point_str] ->
        case String.split(point_str, ",") do
          [lat_str, lon_str | _] ->
            with {lat, _} <- Float.parse(String.trim(lat_str)),
                 {lon, _} <- Float.parse(String.trim(lon_str)) do
              [{lat, lon}]
            else
              _ -> []
            end

          _ ->
            []
        end
    end)
  end

  defp extract_name(raw) do
    case Regex.run(@name_regex, raw) do
      [_, name] when name != "" -> name
      _ -> nil
    end
  end

  @color_regex_cache %{}

  defp extract_color(raw, element_name) do
    regex =
      Map.get_lazy(@color_regex_cache, element_name, fn ->
        Regex.compile!("<#{element_name}[^>]*value=\"([^\"]+)\"")
      end)

    case Regex.run(regex, raw) do
      [_, value_str] ->
        case Integer.parse(value_str) do
          {value, _} -> argb_to_css(value)
          :error -> nil
        end

      nil ->
        nil
    end
  end

  defp extract_remarks(raw) do
    case Regex.run(@remarks_regex, raw) do
      [_, text] when text != "" -> text
      _ -> nil
    end
  end

  @ellipse_major_regex ~r/<Shape[^>]*ellipseMajor="([^"]+)"/
  @ellipse_minor_regex ~r/<Shape[^>]*ellipseMinor="([^"]+)"/

  defp extract_circle_radius(raw, vertices, center) do
    # Try ellipse attributes first (ATAK circle detail)
    major = extract_float_attr(raw, @ellipse_major_regex)
    minor = extract_float_attr(raw, @ellipse_minor_regex)

    cond do
      major && minor ->
        # Average of semi-axes as radius (meters)
        (major + minor) / 2

      major ->
        major

      length(vertices) > 0 ->
        # Fall back: compute radius from center to first vertex using Haversine
        {clat, clon} = center
        {vlat, vlon} = hd(vertices)
        haversine_distance(clat, clon, vlat, vlon)

      true ->
        nil
    end
  end

  defp extract_float_attr(raw, regex) do
    case Regex.run(regex, raw) do
      [_, value_str] ->
        case Float.parse(value_str) do
          {f, _} when f > 0 -> f
          _ -> nil
        end

      nil ->
        nil
    end
  end

  @earth_radius_m 6_371_000.0

  defp haversine_distance(lat1, lon1, lat2, lon2) do
    dlat = deg_to_rad(lat2 - lat1)
    dlon = deg_to_rad(lon2 - lon1)
    rlat1 = deg_to_rad(lat1)
    rlat2 = deg_to_rad(lat2)

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(rlat1) * :math.cos(rlat2) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    @earth_radius_m * c
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180.0
end
