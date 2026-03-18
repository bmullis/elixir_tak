defmodule ElixirTAK.Protocol.TakFramerTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Proto
  alias ElixirTAK.Protocol.TakFramer

  @sample_xml ~s(<event version="2.0" uid="test-1" type="a-f-G-U-C" how="m-g" time="2025-01-01T00:00:00Z" start="2025-01-01T00:00:00Z" stale="2025-01-01T00:10:00Z"><point lat="33.5" lon="-111.9" hae="0" ce="9999999" le="9999999"/><detail><contact callsign="Alpha1"/></detail></event>)

  defp sample_protobuf_payload do
    %Proto.TakMessage{
      cot_event: %Proto.CotEvent{
        type: "a-f-G-U-C",
        uid: "test-proto-1",
        how: "m-g",
        send_time: 1_704_067_200_000,
        start_time: 1_704_067_200_000,
        stale_time: 1_704_067_800_000,
        lat: 33.5,
        lon: -111.9,
        hae: 9_999_999.0,
        ce: 9_999_999.0,
        le: 9_999_999.0,
        detail: %Proto.Detail{
          contact: %Proto.Contact{callsign: "ProtoUser"}
        }
      }
    }
    |> Protobuf.encode()
    |> IO.iodata_to_binary()
  end

  defp frame_protobuf(payload), do: TakFramer.frame_protobuf(payload)

  describe "XML mode" do
    test "raw XML without TAK header auto-detects as XML mode" do
      framer = TakFramer.new()
      {events, framer} = TakFramer.push(framer, @sample_xml)

      assert TakFramer.mode(framer) == :xml
      assert length(events) == 1
      assert [{:xml, xml}] = events
      assert xml =~ "test-1"
    end

    test "multiple XML events" do
      framer = TakFramer.new()
      {events, _framer} = TakFramer.push(framer, @sample_xml <> @sample_xml)

      assert length(events) == 2
    end

    test "XML split across pushes" do
      framer = TakFramer.new()
      {part1, part2} = String.split_at(@sample_xml, div(byte_size(@sample_xml), 2))

      {events1, framer} = TakFramer.push(framer, part1)
      assert events1 == []

      {events2, _framer} = TakFramer.push(framer, part2)
      assert length(events2) == 1
    end
  end

  describe "protobuf mode" do
    test "0xBF header auto-detects as protobuf mode" do
      framer = TakFramer.new()
      payload = sample_protobuf_payload()
      framed = frame_protobuf(payload)

      {events, framer} = TakFramer.push(framer, framed)

      assert TakFramer.mode(framer) == :protobuf
      assert length(events) == 1
      assert [{:ok, event, _payload}] = events
      assert event.uid == "test-proto-1"
      assert event.detail.callsign == "ProtoUser"
    end

    test "multiple protobuf messages in one push" do
      framer = TakFramer.new()
      payload = sample_protobuf_payload()
      framed = frame_protobuf(payload) <> frame_protobuf(payload)

      {events, _framer} = TakFramer.push(framer, framed)

      assert length(events) == 2
    end

    test "protobuf message split across pushes" do
      framer = TakFramer.new()
      payload = sample_protobuf_payload()
      framed = frame_protobuf(payload)
      {part1, part2} = String.split_at(framed, div(byte_size(framed), 2))

      {events1, framer} = TakFramer.push(framer, part1)
      assert events1 == []

      {events2, _framer} = TakFramer.push(framer, part2)
      assert length(events2) == 1
    end
  end

  describe "mode detection edge cases" do
    test "empty push returns no events" do
      framer = TakFramer.new()
      {events, framer} = TakFramer.push(framer, <<>>)

      assert events == []
      assert TakFramer.mode(framer) == :detect
    end

    test "single non-0xBF byte triggers XML mode" do
      framer = TakFramer.new()
      {events, framer} = TakFramer.push(framer, "<")

      assert events == []
      assert TakFramer.mode(framer) == :xml
    end
  end

  describe "switch_to_protobuf/1" do
    test "forces protobuf mode after negotiation" do
      framer = TakFramer.new()
      # Start in XML mode
      {_events, framer} = TakFramer.push(framer, @sample_xml)
      assert TakFramer.mode(framer) == :xml

      # Switch to protobuf
      framer = TakFramer.switch_to_protobuf(framer)
      assert TakFramer.mode(framer) == :protobuf

      # Now it should handle protobuf input
      payload = sample_protobuf_payload()
      framed = frame_protobuf(payload)
      {events, _framer} = TakFramer.push(framer, framed)

      assert length(events) == 1
      assert [{:ok, event, _}] = events
      assert event.uid == "test-proto-1"
    end
  end

  describe "varint encode/decode" do
    test "small values" do
      assert TakFramer.encode_varint(0) == <<0>>
      assert TakFramer.encode_varint(1) == <<1>>
      assert TakFramer.encode_varint(127) == <<127>>
    end

    test "multi-byte values" do
      encoded = TakFramer.encode_varint(128)
      assert {:ok, 128, <<>>} = TakFramer.decode_varint(encoded)

      encoded = TakFramer.encode_varint(300)
      assert {:ok, 300, <<>>} = TakFramer.decode_varint(encoded)

      encoded = TakFramer.encode_varint(16384)
      assert {:ok, 16384, <<>>} = TakFramer.decode_varint(encoded)
    end

    test "round-trip for various sizes" do
      for value <- [0, 1, 127, 128, 255, 256, 1000, 16383, 16384, 65535, 100_000] do
        encoded = TakFramer.encode_varint(value)
        assert {:ok, ^value, <<>>} = TakFramer.decode_varint(encoded)
      end
    end

    test "incomplete varint" do
      assert :incomplete = TakFramer.decode_varint(<<>>)
      # High bit set but no continuation
      assert :incomplete = TakFramer.decode_varint(<<0x80>>)
    end
  end

  describe "frame_protobuf/1" do
    test "wraps payload with magic byte and varint length" do
      payload = <<1, 2, 3, 4, 5>>
      framed = TakFramer.frame_protobuf(payload)

      assert <<0xBF, rest::binary>> = framed
      assert {:ok, 5, ^payload} = TakFramer.decode_varint(rest)
    end
  end
end
