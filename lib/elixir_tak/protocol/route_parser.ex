defmodule ElixirTAK.Protocol.RouteParser do
  @moduledoc """
  Extracts structured route data from a CotEvent's raw_detail XML.

  Route events (type `b-m-r`) carry ordered waypoints as `<link>` elements
  with `relation="c"`, stroke color, and metadata inside `<detail>`. This
  module parses those fields into a map suitable for rendering on the
  CesiumJS map.

  ## TAK route format

  Waypoints are `<link>` elements with `relation="c"` and `point="lat,lon"`.
  Their order in the XML defines the route path. Route name comes from
  `<contact callsign="..."/>`. Color uses the same signed 32-bit ARGB
  format as shapes.
  """

  alias ElixirTAK.Protocol.{CotEvent, ShapeParser}

  @type route :: %{
          uid: String.t(),
          name: String.t() | nil,
          waypoints: [{float(), float()}],
          waypoint_count: non_neg_integer(),
          total_distance_m: float(),
          stroke_color: String.t() | nil,
          remarks: String.t() | nil
        }

  @doc """
  Parse a route CotEvent into a structured route map.

  Returns `{:ok, route}` or `:error`.
  """
  @spec parse(%CotEvent{}) :: {:ok, route()} | :error
  def parse(%CotEvent{type: "b-m-r" <> _, raw_detail: raw} = event)
      when is_binary(raw) do
    waypoints = extract_waypoints(raw)

    route = %{
      uid: event.uid,
      name: extract_name(raw),
      waypoints: waypoints,
      waypoint_count: length(waypoints),
      total_distance_m: total_distance(waypoints),
      stroke_color: extract_color(raw),
      remarks: extract_remarks(raw)
    }

    {:ok, route}
  end

  def parse(_), do: :error

  @doc """
  Like `parse/1` but returns the map directly or nil.
  """
  @spec parse!(%CotEvent{}) :: route() | nil
  def parse!(%CotEvent{} = event) do
    case parse(event) do
      {:ok, route} -> route
      :error -> nil
    end
  end

  # -- Private ---------------------------------------------------------------

  @link_regex ~r/<link\s([^>]*)\/>/
  @name_regex ~r/<contact\s[^>]*callsign="([^"]+)"/
  @remarks_regex ~r/<remarks[^>]*>(.*?)<\/remarks>/s
  @color_regex ~r/<strokeColor[^>]*value="([^"]+)"/

  defp extract_waypoints(raw) do
    Regex.scan(@link_regex, raw)
    |> Enum.filter(fn [_, attrs] -> attrs =~ ~r/relation="c"/ end)
    |> Enum.flat_map(fn [_, attrs] ->
      case Regex.run(~r/point="([^"]+)"/, attrs) do
        [_, point_str] -> parse_point(point_str)
        nil -> []
      end
    end)
  end

  defp parse_point(point_str) do
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
  end

  defp extract_name(raw) do
    case Regex.run(@name_regex, raw) do
      [_, name] when name != "" -> name
      _ -> nil
    end
  end

  defp extract_color(raw) do
    case Regex.run(@color_regex, raw) do
      [_, value_str] ->
        case Integer.parse(value_str) do
          {value, _} -> ShapeParser.argb_to_css(value)
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

  defp total_distance(waypoints) when length(waypoints) < 2, do: 0.0

  defp total_distance(waypoints) do
    waypoints
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [{lat1, lon1}, {lat2, lon2}], acc ->
      acc + haversine_distance(lat1, lon1, lat2, lon2)
    end)
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
