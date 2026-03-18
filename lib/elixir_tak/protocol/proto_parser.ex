defmodule ElixirTAK.Protocol.ProtoParser do
  @moduledoc """
  Parses a TAK protobuf binary (serialized TakMessage) into a `%CotEvent{}` struct.

  The protobuf Detail message has structured fields for common elements (contact,
  group, track, etc.) AND an `xmlDetail` string for arbitrary XML that doesn't fit
  the structured fields. We reconstruct `raw_detail` from both sources so the
  CotEvent is indistinguishable from one parsed from XML.
  """

  alias ElixirTAK.Proto
  alias ElixirTAK.Protocol.CotEvent

  @sentinel 9_999_999.0

  @doc """
  Parse a protobuf TakMessage binary into a CotEvent struct.
  Returns `{:ok, %CotEvent{}}` or `{:error, reason}`.
  """
  def parse(binary) when is_binary(binary) do
    with {:ok, tak_msg} <- decode_tak_message(binary),
         {:ok, event} <- convert_to_cot_event(tak_msg) do
      {:ok, event}
    end
  end

  defp decode_tak_message(binary) do
    {:ok, Proto.TakMessage.decode(binary)}
  rescue
    _ -> {:error, :protobuf_decode_error}
  end

  defp convert_to_cot_event(%Proto.TakMessage{cot_event: nil}) do
    {:error, :missing_cot_event}
  end

  defp convert_to_cot_event(%Proto.TakMessage{cot_event: cot}) do
    detail = cot.detail

    {:ok,
     %CotEvent{
       uid: cot.uid,
       type: cot.type,
       how: presence(cot.how),
       time: millis_to_datetime(cot.send_time),
       start: millis_to_datetime(cot.start_time),
       stale: millis_to_datetime(cot.stale_time),
       point: %{
         lat: cot.lat,
         lon: cot.lon,
         hae: strip_sentinel(cot.hae),
         ce: strip_sentinel(cot.ce),
         le: strip_sentinel(cot.le)
       },
       detail: extract_detail(detail),
       raw_detail: build_raw_detail(detail)
     }}
  end

  defp extract_detail(nil), do: nil

  defp extract_detail(%Proto.Detail{} = detail) do
    %{
      callsign: extract_callsign(detail.contact),
      group: extract_group(detail.group),
      track: extract_track(detail.track)
    }
  end

  defp extract_callsign(nil), do: nil
  defp extract_callsign(%Proto.Contact{callsign: ""}), do: nil
  defp extract_callsign(%Proto.Contact{callsign: cs}), do: cs

  defp extract_group(nil), do: nil
  defp extract_group(%Proto.Group{name: ""}), do: nil
  defp extract_group(%Proto.Group{name: name, role: role}), do: %{name: name, role: role}

  defp extract_track(nil), do: nil

  defp extract_track(%Proto.Track{speed: speed, course: course}) do
    %{speed: speed, course: course}
  end

  @doc """
  Reconstruct `<detail>...</detail>` XML from protobuf Detail.

  Structured fields (contact, group, track, takv, status, precisionlocation) are
  converted to their XML equivalents. The `xmlDetail` passthrough is inserted
  as-is (it contains inner detail children without the outer `<detail>` wrapper).
  """
  def build_raw_detail(nil), do: nil

  def build_raw_detail(%Proto.Detail{} = detail) do
    children =
      [
        contact_xml(detail.contact),
        group_xml(detail.group),
        track_xml(detail.track),
        takv_xml(detail.takv),
        status_xml(detail.status),
        precision_location_xml(detail.precision_location),
        xml_detail_passthrough(detail.xml_detail)
      ]
      |> Enum.reject(&is_nil/1)

    case children do
      [] -> "<detail/>"
      parts -> "<detail>" <> Enum.join(parts) <> "</detail>"
    end
  end

  defp contact_xml(nil), do: nil
  defp contact_xml(%Proto.Contact{callsign: "", endpoint: ""}), do: nil

  defp contact_xml(%Proto.Contact{} = c) do
    attrs =
      [
        opt_attr("endpoint", c.endpoint),
        opt_attr("callsign", c.callsign)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    "<contact#{attrs}/>"
  end

  defp group_xml(nil), do: nil
  defp group_xml(%Proto.Group{name: ""}), do: nil

  defp group_xml(%Proto.Group{} = g) do
    "<__group#{opt_attr("name", g.name)}#{opt_attr("role", g.role)}/>"
  end

  defp track_xml(nil), do: nil

  defp track_xml(%Proto.Track{} = t) do
    "<track#{opt_attr("speed", t.speed)}#{opt_attr("course", t.course)}/>"
  end

  defp takv_xml(nil), do: nil
  defp takv_xml(%Proto.Takv{device: "", platform: "", os: "", version: ""}), do: nil

  defp takv_xml(%Proto.Takv{} = t) do
    attrs =
      [
        opt_attr("device", t.device),
        opt_attr("platform", t.platform),
        opt_attr("os", t.os),
        opt_attr("version", t.version)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    "<takv#{attrs}/>"
  end

  defp status_xml(nil), do: nil
  defp status_xml(%Proto.Status{battery: 0}), do: nil
  defp status_xml(%Proto.Status{battery: b}), do: ~s(<status battery="#{b}"/>)

  defp precision_location_xml(nil), do: nil

  defp precision_location_xml(%Proto.PrecisionLocation{geopointsrc: "", altsrc: ""}),
    do: nil

  defp precision_location_xml(%Proto.PrecisionLocation{} = pl) do
    attrs =
      [
        opt_attr("geopointsrc", pl.geopointsrc),
        opt_attr("altsrc", pl.altsrc)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    "<precisionlocation#{attrs}/>"
  end

  defp xml_detail_passthrough(""), do: nil
  defp xml_detail_passthrough(xml) when is_binary(xml), do: xml
  defp xml_detail_passthrough(_), do: nil

  defp opt_attr(_name, ""), do: nil
  defp opt_attr(_name, nil), do: nil
  defp opt_attr(name, val) when is_float(val), do: ~s( #{name}="#{val}")
  defp opt_attr(name, val), do: ~s( #{name}="#{val}")

  defp millis_to_datetime(0), do: nil

  defp millis_to_datetime(ms) when is_integer(ms) and ms > 0 do
    DateTime.from_unix!(ms, :millisecond)
  end

  defp millis_to_datetime(_), do: nil

  defp strip_sentinel(val) when val >= @sentinel, do: nil
  defp strip_sentinel(val) when val == 0.0, do: nil
  defp strip_sentinel(val), do: val

  defp presence(""), do: nil
  defp presence(s), do: s
end
