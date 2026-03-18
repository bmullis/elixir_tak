defmodule ElixirTAK.Protocol.CotValidator do
  @moduledoc """
  Validates a CotEvent struct before it enters PubSub or further processing.

  Returns `{:ok, event}` or `{:error, reasons}` where reasons is a list of
  validation error atoms.
  """

  alias ElixirTAK.Protocol.CotEvent

  @type_pattern ~r/\A[a-zA-Z0-9](-[a-zA-Z0-9]+)*\z/

  @doc """
  Validate a CotEvent struct. Returns `{:ok, event}` on success or
  `{:error, reasons}` with a list of error atoms.
  """
  def validate(%CotEvent{} = event) do
    errors =
      []
      |> check_lat(event)
      |> check_lon(event)
      |> check_start_stale(event)
      |> check_type(event)

    case errors do
      [] -> {:ok, event}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp check_lat(errors, %CotEvent{point: %{lat: lat}})
       when is_number(lat) and lat >= -90 and lat <= 90,
       do: errors

  defp check_lat(errors, _event), do: [:invalid_lat | errors]

  defp check_lon(errors, %CotEvent{point: %{lon: lon}})
       when is_number(lon) and lon >= -180 and lon <= 180,
       do: errors

  defp check_lon(errors, _event), do: [:invalid_lon | errors]

  defp check_start_stale(errors, %CotEvent{start: nil}), do: errors
  defp check_start_stale(errors, %CotEvent{stale: nil}), do: errors

  defp check_start_stale(errors, %CotEvent{start: start, stale: stale}) do
    case DateTime.compare(start, stale) do
      :gt -> [:start_after_stale | errors]
      _ -> errors
    end
  end

  defp check_type(errors, %CotEvent{type: type}) when is_binary(type) do
    if Regex.match?(@type_pattern, type),
      do: errors,
      else: [:invalid_type | errors]
  end

  defp check_type(errors, _event), do: [:invalid_type | errors]
end
