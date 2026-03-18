defmodule ElixirTAK.Protocol.CotEncoder do
  @moduledoc """
  Encodes a CotEvent struct into CoT XML as iodata.

  Uses IO lists for efficient output — call `IO.iodata_to_binary/1`
  if you need a binary string.
  """

  alias ElixirTAK.Protocol.CotEvent

  @sentinel 9_999_999.0

  @doc """
  Encode a CotEvent struct into CoT XML iodata.
  """
  def encode(%CotEvent{} = event) do
    [
      "<event",
      attr("uid", event.uid),
      attr("type", event.type),
      attr("how", event.how),
      attr("time", event.time),
      attr("start", event.start),
      attr("stale", event.stale),
      attr("version", "2.0"),
      ">",
      encode_point(event.point),
      encode_detail(event),
      "</event>"
    ]
  end

  defp encode_point(point) do
    [
      "<point",
      attr("lat", point.lat),
      attr("lon", point.lon),
      attr("hae", point.hae || @sentinel),
      attr("ce", point.ce || @sentinel),
      attr("le", point.le || @sentinel),
      "/>"
    ]
  end

  defp encode_detail(%CotEvent{raw_detail: raw}) when is_binary(raw), do: raw
  defp encode_detail(%CotEvent{detail: nil}), do: []
  defp encode_detail(%CotEvent{detail: detail}), do: encode_detail_structured(detail)

  defp encode_detail_structured(detail) do
    children = [
      encode_contact(detail.callsign),
      encode_group(detail.group),
      encode_track(detail.track)
    ]

    ["<detail>", children, "</detail>"]
  end

  defp encode_contact(nil), do: []
  defp encode_contact(callsign), do: ["<contact", attr("callsign", callsign), "/>"]

  defp encode_group(nil), do: []

  defp encode_group(group) do
    ["<__group", attr("name", group.name), attr("role", group.role), "/>"]
  end

  defp encode_track(nil), do: []

  defp encode_track(track) do
    ["<track", attr("speed", track.speed), attr("course", track.course), "/>"]
  end

  defp attr(_name, nil), do: []
  defp attr(name, %DateTime{} = dt), do: [" ", name, "=\"", DateTime.to_iso8601(dt), "\""]
  defp attr(name, val) when is_float(val), do: [" ", name, "=\"", Float.to_string(val), "\""]
  defp attr(name, val), do: [" ", name, "=\"", escape(to_string(val)), "\""]

  defp escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
