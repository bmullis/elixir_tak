defmodule ElixirTAK.Protocol.GeofenceParser do
  @moduledoc """
  Extracts geofence metadata from a CotEvent's raw_detail XML.

  Geofence definitions are shape events (type `u-d-*`) that carry a
  `<__geofence>` element in their detail XML. The polygon geometry is
  identical to regular shapes and is delegated to `ShapeParser`. This
  module adds the geofence-specific fields: trigger, monitor type,
  boundary type, and elevation bounds.

  ## Geofence trigger types

  - `Entry` - fires when a client enters the polygon
  - `Exit` - fires when a client leaves the polygon
  - `Both` - fires on both entry and exit
  """

  alias ElixirTAK.Protocol.{CotEvent, ShapeParser}

  @type geofence :: %{
          uid: String.t(),
          name: String.t() | nil,
          shape_type: :polygon | :rectangle | :circle | :freeform,
          vertices: [{float(), float()}],
          stroke_color: String.t() | nil,
          fill_color: String.t() | nil,
          remarks: String.t() | nil,
          center: {float(), float()} | nil,
          radius: float() | nil,
          trigger: String.t() | nil,
          monitor_type: String.t() | nil,
          boundary_type: String.t() | nil,
          min_elevation: float() | nil,
          max_elevation: float() | nil
        }

  @geofence_regex ~r/<__geofence[\s>]/

  @doc """
  Returns true if the event's raw_detail contains a `<__geofence` element.
  """
  @spec geofence_event?(%CotEvent{}) :: boolean()
  def geofence_event?(%CotEvent{type: "u-d-" <> _, raw_detail: raw}) when is_binary(raw) do
    Regex.match?(@geofence_regex, raw)
  end

  def geofence_event?(_), do: false

  @doc """
  Parse a geofence CotEvent into a structured map with shape + geofence fields.

  Returns `{:ok, geofence}` or `:error`.
  """
  @spec parse(%CotEvent{}) :: {:ok, geofence()} | :error
  def parse(%CotEvent{raw_detail: raw} = event) when is_binary(raw) do
    if Regex.match?(@geofence_regex, raw) do
      case ShapeParser.parse(event) do
        {:ok, shape} ->
          geofence =
            Map.merge(shape, %{
              trigger: extract_attr(raw, "trigger"),
              monitor_type: extract_attr(raw, "monitorType"),
              boundary_type: extract_attr(raw, "boundaryType"),
              min_elevation: extract_float_attr(raw, "minElevation"),
              max_elevation: extract_float_attr(raw, "maxElevation")
            })

          {:ok, geofence}

        :error ->
          :error
      end
    else
      :error
    end
  end

  def parse(_), do: :error

  @doc """
  Like `parse/1` but returns the map directly or nil.
  """
  @spec parse!(%CotEvent{}) :: geofence() | nil
  def parse!(%CotEvent{} = event) do
    case parse(event) do
      {:ok, geofence} -> geofence
      :error -> nil
    end
  end

  # -- Private ---------------------------------------------------------------

  defp extract_attr(raw, attr_name) do
    regex = Regex.compile!("<__geofence[^>]*#{attr_name}=\"([^\"]+)\"")

    case Regex.run(regex, raw) do
      [_, value] -> value
      nil -> nil
    end
  end

  defp extract_float_attr(raw, attr_name) do
    case extract_attr(raw, attr_name) do
      nil ->
        nil

      value_str ->
        case Float.parse(value_str) do
          {f, _} -> f
          :error -> nil
        end
    end
  end
end
