defmodule ElixirTAK.Protocol.CotParser do
  @moduledoc """
  Parses Cursor-on-Target (CoT) XML messages into structured Elixir maps.

  CoT is the wire protocol used by TAK (Team Awareness Kit) clients and servers.
  Every message is an <event> element with a mandatory <point> and optional <detail>.
  """

  import SweetXml, except: [parse: 1]

  alias ElixirTAK.Protocol.CotEvent

  @doc """
  Parse a CoT XML binary into a CotEvent struct.
  Returns {:ok, %CotEvent{}} or {:error, reason}.
  """
  def parse(xml) when is_binary(xml) do
    doc = SweetXml.parse(xml)

    case xpath(doc, ~x"/event"e) do
      nil -> {:error, :not_a_cot_event}
      event -> build_event(xml, event)
    end
  catch
    :exit, _ -> {:error, :xml_parse_error}
  end

  defp build_event(xml, event) do
    with {:ok, base} <- extract_base_attrs(event),
         {:ok, point} <- extract_point(event) do
      {:ok,
       struct!(
         CotEvent,
         Map.merge(base, %{
           point: point,
           detail: extract_detail(event),
           raw_detail: extract_raw_detail(xml)
         })
       )}
    end
  end

  defp extract_base_attrs(event) do
    uid = xpath(event, ~x"./@uid"so)
    type = xpath(event, ~x"./@type"so)

    if presence(uid) && presence(type) do
      {:ok,
       %{
         uid: uid,
         type: type,
         how: presence(xpath(event, ~x"./@how"so)),
         time: event |> xpath(~x"./@time"so) |> parse_time(),
         start: event |> xpath(~x"./@start"so) |> parse_time(),
         stale: event |> xpath(~x"./@stale"so) |> parse_time()
       }}
    else
      {:error, :missing_required_attrs}
    end
  end

  defp extract_point(event) do
    case xpath(event, ~x"./point"eo) do
      nil ->
        {:error, :missing_point}

      point ->
        {:ok,
         %{
           lat: point |> xpath(~x"./@lat"so) |> parse_float(),
           lon: point |> xpath(~x"./@lon"so) |> parse_float(),
           hae: point |> xpath(~x"./@hae"so) |> parse_float() |> strip_sentinel(),
           ce: point |> xpath(~x"./@ce"so) |> parse_float() |> strip_sentinel(),
           le: point |> xpath(~x"./@le"so) |> parse_float() |> strip_sentinel()
         }}
    end
  end

  defp extract_detail(event) do
    case xpath(event, ~x"./detail"eo) do
      nil ->
        nil

      detail ->
        %{
          callsign: xpath(detail, ~x"./contact/@callsign"so),
          group: extract_group(detail),
          track: extract_track(detail)
        }
    end
  end

  defp extract_group(detail) do
    case xpath(detail, ~x"./__group"eo) do
      nil -> nil
      group -> %{name: xpath(group, ~x"./@name"so), role: xpath(group, ~x"./@role"so)}
    end
  end

  defp extract_track(detail) do
    case xpath(detail, ~x"./track"eo) do
      nil ->
        nil

      track ->
        %{
          speed: track |> xpath(~x"./@speed"so) |> parse_float(),
          course: track |> xpath(~x"./@course"so) |> parse_float()
        }
    end
  end

  @detail_regex ~r/<detail[\s>].*?<\/detail>|<detail\s*\/>/s

  defp extract_raw_detail(xml) do
    case Regex.run(@detail_regex, xml) do
      [match] -> match
      nil -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s), do: s

  @sentinel 9_999_999.0

  defp strip_sentinel(@sentinel), do: nil
  defp strip_sentinel(val), do: val

  defp parse_float(nil), do: nil

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_time(nil), do: nil

  defp parse_time(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
