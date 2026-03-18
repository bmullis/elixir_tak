defmodule ElixirTAK.Protocol.ProtoEncoderTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, ProtoEncoder, ProtoParser}

  @sample_event %CotEvent{
    uid: "ANDROID-abc123",
    type: "a-f-G-U-C",
    how: "m-g",
    time: ~U[2025-01-01 00:00:00Z],
    start: ~U[2025-01-01 00:00:00Z],
    stale: ~U[2025-01-01 00:10:00Z],
    point: %{lat: 33.5, lon: -111.9, hae: 100.5, ce: nil, le: nil},
    detail: %{
      callsign: "Alpha1",
      group: %{name: "Cyan", role: "Team Member"},
      track: %{speed: 5.2, course: 180.0}
    },
    raw_detail:
      ~s(<detail><contact callsign="Alpha1"/><__group name="Cyan" role="Team Member"/><track speed="5.2" course="180.0"/></detail>)
  }

  describe "encode/1" do
    test "encodes a CotEvent to protobuf binary" do
      binary = ProtoEncoder.encode(@sample_event)
      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "round-trip: CotEvent -> protobuf -> CotEvent preserves fields" do
      binary = ProtoEncoder.encode(@sample_event)
      {:ok, parsed} = ProtoParser.parse(binary)

      assert parsed.uid == @sample_event.uid
      assert parsed.type == @sample_event.type
      assert parsed.how == @sample_event.how
      assert parsed.point.lat == @sample_event.point.lat
      assert parsed.point.lon == @sample_event.point.lon
      assert parsed.point.hae == @sample_event.point.hae
      assert parsed.detail.callsign == "Alpha1"
      assert parsed.detail.group == %{name: "Cyan", role: "Team Member"}
      assert parsed.detail.track == %{speed: 5.2, course: 180.0}
    end

    test "round-trip preserves timestamps" do
      binary = ProtoEncoder.encode(@sample_event)
      {:ok, parsed} = ProtoParser.parse(binary)

      # Millis round-trip may add .000 fractional seconds; compare as unix timestamps
      assert DateTime.to_unix(parsed.time) == DateTime.to_unix(@sample_event.time)
      assert DateTime.to_unix(parsed.start) == DateTime.to_unix(@sample_event.start)
      assert DateTime.to_unix(parsed.stale) == DateTime.to_unix(@sample_event.stale)
    end

    test "sentinel values restored for nil ce/le/hae" do
      binary = ProtoEncoder.encode(@sample_event)
      {:ok, parsed} = ProtoParser.parse(binary)

      # nil -> sentinel -> nil round-trip
      assert parsed.point.ce == nil
      assert parsed.point.le == nil
    end

    test "encodes event with raw_detail containing takv and remarks" do
      event = %{
        @sample_event
        | raw_detail:
            ~s(<detail><contact callsign="Alpha1"/><takv device="Pixel" platform="ATAK-CIV" os="Android" version="4.10"/><remarks>test note</remarks></detail>)
      }

      binary = ProtoEncoder.encode(event)
      {:ok, parsed} = ProtoParser.parse(binary)

      # takv should be extracted into structured field and back
      assert parsed.raw_detail =~ ~s(device="Pixel")
      # remarks should survive as xmlDetail passthrough
      assert parsed.raw_detail =~ "<remarks>test note</remarks>"
    end

    test "encodes event with nil raw_detail" do
      event = %{@sample_event | raw_detail: nil}
      binary = ProtoEncoder.encode(event)
      {:ok, parsed} = ProtoParser.parse(binary)

      assert parsed.uid == @sample_event.uid
      assert parsed.detail.callsign == "Alpha1"
    end

    test "encodes event with nil detail and nil raw_detail" do
      event = %CotEvent{
        uid: "test-1",
        type: "a-f-G-U-C",
        how: "m-g",
        time: ~U[2025-01-01 00:00:00Z],
        start: ~U[2025-01-01 00:00:00Z],
        stale: ~U[2025-01-01 00:10:00Z],
        point: %{lat: 33.5, lon: -111.9, hae: nil, ce: nil, le: nil},
        detail: nil,
        raw_detail: nil
      }

      binary = ProtoEncoder.encode(event)
      {:ok, parsed} = ProtoParser.parse(binary)

      assert parsed.uid == "test-1"
    end
  end

  describe "extract_xml_detail/2" do
    test "strips known elements and keeps unknown ones" do
      raw =
        ~s(<detail><contact callsign="A"/><__group name="Cyan" role="TM"/><track speed="1" course="2"/><remarks>hello</remarks><usericon iconsetpath="abc"/></detail>)

      result = ProtoEncoder.extract_xml_detail(raw, nil)
      assert result =~ "<remarks>hello</remarks>"
      assert result =~ "<usericon"
      refute result =~ "<contact"
      refute result =~ "<__group"
      refute result =~ "<track"
    end

    test "returns empty string for nil raw_detail" do
      assert ProtoEncoder.extract_xml_detail(nil, nil) == ""
    end

    test "returns empty string when all elements are known" do
      raw = ~s(<detail><contact callsign="A"/></detail>)
      result = ProtoEncoder.extract_xml_detail(raw, nil)
      assert result == ""
    end
  end
end
