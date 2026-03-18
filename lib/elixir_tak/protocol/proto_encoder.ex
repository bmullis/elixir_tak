defmodule ElixirTAK.Protocol.ProtoEncoder do
  @moduledoc """
  Encodes a `%CotEvent{}` struct into a TAK protobuf binary (serialized TakMessage).

  Converts DateTime timestamps to milliseconds since epoch, restores sentinel values
  for unknown hae/ce/le, and splits `raw_detail` XML back into structured protobuf
  fields + xmlDetail passthrough.
  """

  alias ElixirTAK.Proto
  alias ElixirTAK.Protocol.CotEvent

  @sentinel 9_999_999.0

  @doc """
  Encode a CotEvent struct into a protobuf TakMessage binary.
  """
  def encode(%CotEvent{} = event) do
    %Proto.TakMessage{
      cot_event: %Proto.CotEvent{
        type: event.type || "",
        uid: event.uid || "",
        how: event.how || "",
        send_time: datetime_to_millis(event.time),
        start_time: datetime_to_millis(event.start),
        stale_time: datetime_to_millis(event.stale),
        lat: event.point.lat || 0.0,
        lon: event.point.lon || 0.0,
        hae: restore_sentinel(event.point.hae),
        ce: restore_sentinel(event.point.ce),
        le: restore_sentinel(event.point.le),
        detail: build_detail(event)
      }
    }
    |> Proto.TakMessage.encode()
    |> IO.iodata_to_binary()
  end

  defp build_detail(%CotEvent{raw_detail: raw, detail: detail}) do
    %Proto.Detail{
      contact: build_contact(detail),
      group: build_group(detail),
      track: build_track(detail),
      takv: extract_takv(raw),
      status: extract_status(raw),
      precision_location: extract_precision_location(raw),
      xml_detail: extract_xml_detail(raw, detail)
    }
  end

  defp build_contact(nil), do: nil
  defp build_contact(%{callsign: nil}), do: nil
  defp build_contact(%{callsign: ""}), do: nil

  defp build_contact(%{callsign: cs}) do
    %Proto.Contact{callsign: cs, endpoint: ""}
  end

  # Dashboard-created events nest callsign under :contact
  defp build_contact(%{contact: %{callsign: cs}}) when is_binary(cs) do
    %Proto.Contact{callsign: cs, endpoint: ""}
  end

  defp build_contact(_), do: nil

  defp build_group(nil), do: nil
  defp build_group(%{group: nil}), do: nil

  defp build_group(%{group: %{name: name, role: role}}) do
    %Proto.Group{name: name || "", role: role || ""}
  end

  defp build_group(_), do: nil

  defp build_track(nil), do: nil
  defp build_track(%{track: nil}), do: nil

  defp build_track(%{track: %{speed: speed, course: course}}) do
    %Proto.Track{speed: speed || 0.0, course: course || 0.0}
  end

  defp build_track(_), do: nil

  # Extract structured fields from raw_detail XML for protobuf encoding.
  # These elements have dedicated protobuf fields and should NOT go into xmlDetail.
  @known_elements ~w(contact __group track takv status precisionlocation)

  defp extract_takv(nil), do: nil

  defp extract_takv(raw) when is_binary(raw) do
    case Regex.run(~r/<takv([^>]*)\/>/s, raw) do
      [_, attrs] ->
        %Proto.Takv{
          device: attr_value(attrs, "device"),
          platform: attr_value(attrs, "platform"),
          os: attr_value(attrs, "os"),
          version: attr_value(attrs, "version")
        }

      _ ->
        nil
    end
  end

  defp extract_status(nil), do: nil

  defp extract_status(raw) when is_binary(raw) do
    case Regex.run(~r/<status[^>]*battery="(\d+)"[^>]*\/>/s, raw) do
      [_, battery] -> %Proto.Status{battery: String.to_integer(battery)}
      _ -> nil
    end
  end

  defp extract_precision_location(nil), do: nil

  defp extract_precision_location(raw) when is_binary(raw) do
    case Regex.run(~r/<precisionlocation([^>]*)\/>/s, raw) do
      [_, attrs] ->
        %Proto.PrecisionLocation{
          geopointsrc: attr_value(attrs, "geopointsrc"),
          altsrc: attr_value(attrs, "altsrc")
        }

      _ ->
        nil
    end
  end

  @doc """
  Extract the xmlDetail passthrough string from raw_detail.

  Strips the outer `<detail>...</detail>` wrapper and removes elements that have
  dedicated protobuf fields (contact, __group, track, takv, status, precisionlocation).
  The remaining inner XML becomes the `xmlDetail` field.
  """
  def extract_xml_detail(nil, _detail), do: ""

  def extract_xml_detail(raw, _detail) when is_binary(raw) do
    raw
    |> strip_detail_wrapper()
    |> strip_known_elements()
    |> String.trim()
  end

  defp strip_detail_wrapper(raw) do
    raw
    |> String.replace(~r/^<detail[^>]*>/, "")
    |> String.replace(~r/<\/detail>\s*$/, "")
    |> String.replace(~r/^<detail\s*\/>\s*$/, "")
  end

  defp strip_known_elements(xml) do
    Enum.reduce(@known_elements, xml, fn tag, acc ->
      # Remove self-closing: <tag ... />
      acc = Regex.replace(~r/<#{tag}[^>]*\/>/s, acc, "")
      # Remove with body: <tag ...>...</tag>
      Regex.replace(~r/<#{tag}[^>]*>.*?<\/#{tag}>/s, acc, "")
    end)
  end

  defp attr_value(attrs_str, name) do
    case Regex.run(~r/#{name}="([^"]*)"/, attrs_str) do
      [_, val] -> val
      _ -> ""
    end
  end

  defp datetime_to_millis(nil), do: 0

  defp datetime_to_millis(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  defp restore_sentinel(nil), do: @sentinel
  defp restore_sentinel(val), do: val
end
