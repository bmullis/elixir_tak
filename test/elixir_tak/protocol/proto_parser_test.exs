defmodule ElixirTAK.Protocol.ProtoParserTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Proto
  alias ElixirTAK.Protocol.{CotEvent, ProtoParser}

  @sample_tak_message %Proto.TakMessage{
    cot_event: %Proto.CotEvent{
      type: "a-f-G-U-C",
      uid: "ANDROID-abc123",
      how: "m-g",
      send_time: 1_704_067_200_000,
      start_time: 1_704_067_200_000,
      stale_time: 1_704_067_800_000,
      lat: 33.5,
      lon: -111.9,
      hae: 100.5,
      ce: 9_999_999.0,
      le: 9_999_999.0,
      detail: %Proto.Detail{
        xml_detail: "<remarks>hello</remarks>",
        contact: %Proto.Contact{callsign: "Alpha1", endpoint: ""},
        group: %Proto.Group{name: "Cyan", role: "Team Member"},
        track: %Proto.Track{speed: 5.2, course: 180.0}
      }
    }
  }

  defp encode_sample, do: Protobuf.encode(@sample_tak_message) |> IO.iodata_to_binary()

  describe "parse/1" do
    test "parses a valid protobuf TakMessage into CotEvent" do
      {:ok, event} = ProtoParser.parse(encode_sample())

      assert %CotEvent{} = event
      assert event.uid == "ANDROID-abc123"
      assert event.type == "a-f-G-U-C"
      assert event.how == "m-g"
    end

    test "converts timestamps from millis to DateTime" do
      {:ok, event} = ProtoParser.parse(encode_sample())

      assert event.time == ~U[2024-01-01 00:00:00.000Z]
      assert event.start == ~U[2024-01-01 00:00:00.000Z]
      assert event.stale == ~U[2024-01-01 00:10:00.000Z]
    end

    test "extracts point coordinates" do
      {:ok, event} = ProtoParser.parse(encode_sample())

      assert event.point.lat == 33.5
      assert event.point.lon == -111.9
      assert event.point.hae == 100.5
    end

    test "strips sentinel values for ce/le" do
      {:ok, event} = ProtoParser.parse(encode_sample())

      assert event.point.ce == nil
      assert event.point.le == nil
    end

    test "extracts structured detail fields" do
      {:ok, event} = ProtoParser.parse(encode_sample())

      assert event.detail.callsign == "Alpha1"
      assert event.detail.group == %{name: "Cyan", role: "Team Member"}
      assert event.detail.track == %{speed: 5.2, course: 180.0}
    end

    test "reconstructs raw_detail from structured fields and xmlDetail" do
      {:ok, event} = ProtoParser.parse(encode_sample())

      assert event.raw_detail =~ "<contact"
      assert event.raw_detail =~ ~s(callsign="Alpha1")
      assert event.raw_detail =~ "<__group"
      assert event.raw_detail =~ ~s(name="Cyan")
      assert event.raw_detail =~ "<track"
      assert event.raw_detail =~ "<remarks>hello</remarks>"
      assert String.starts_with?(event.raw_detail, "<detail>")
      assert String.ends_with?(event.raw_detail, "</detail>")
    end

    test "handles missing detail" do
      msg = %Proto.TakMessage{
        cot_event: %Proto.CotEvent{
          type: "a-f-G-U-C",
          uid: "test-1",
          how: "m-g",
          send_time: 1_704_067_200_000,
          start_time: 1_704_067_200_000,
          stale_time: 1_704_067_800_000,
          lat: 33.5,
          lon: -111.9,
          hae: 9_999_999.0,
          ce: 9_999_999.0,
          le: 9_999_999.0
        }
      }

      binary = Protobuf.encode(msg) |> IO.iodata_to_binary()
      {:ok, event} = ProtoParser.parse(binary)

      assert event.detail == nil
      assert event.raw_detail == nil
    end

    test "handles zero timestamps as nil" do
      msg = %Proto.TakMessage{
        cot_event: %Proto.CotEvent{
          type: "a-f-G-U-C",
          uid: "test-1",
          lat: 33.5,
          lon: -111.9,
          hae: 9_999_999.0,
          ce: 9_999_999.0,
          le: 9_999_999.0
        }
      }

      binary = Protobuf.encode(msg) |> IO.iodata_to_binary()
      {:ok, event} = ProtoParser.parse(binary)

      assert event.time == nil
      assert event.start == nil
      assert event.stale == nil
    end

    test "handles missing cot_event" do
      msg = %Proto.TakMessage{cot_event: nil}
      binary = Protobuf.encode(msg) |> IO.iodata_to_binary()

      assert {:error, :missing_cot_event} = ProtoParser.parse(binary)
    end

    test "returns error for invalid binary" do
      assert {:error, :protobuf_decode_error} = ProtoParser.parse(<<0, 1, 2, 3>>)
    end

    test "handles empty how as nil" do
      msg = %Proto.TakMessage{
        cot_event: %Proto.CotEvent{
          type: "a-f-G-U-C",
          uid: "test-1",
          how: "",
          lat: 33.5,
          lon: -111.9,
          hae: 9_999_999.0,
          ce: 9_999_999.0,
          le: 9_999_999.0
        }
      }

      binary = Protobuf.encode(msg) |> IO.iodata_to_binary()
      {:ok, event} = ProtoParser.parse(binary)

      assert event.how == nil
    end

    test "includes takv and status in raw_detail" do
      msg = %Proto.TakMessage{
        cot_event: %Proto.CotEvent{
          type: "a-f-G-U-C",
          uid: "test-1",
          lat: 33.5,
          lon: -111.9,
          hae: 9_999_999.0,
          ce: 9_999_999.0,
          le: 9_999_999.0,
          detail: %Proto.Detail{
            takv: %Proto.Takv{
              device: "Pixel",
              platform: "ATAK-CIV",
              os: "Android 14",
              version: "4.10"
            },
            status: %Proto.Status{battery: 85}
          }
        }
      }

      binary = Protobuf.encode(msg) |> IO.iodata_to_binary()
      {:ok, event} = ProtoParser.parse(binary)

      assert event.raw_detail =~ ~s(device="Pixel")
      assert event.raw_detail =~ ~s(battery="85")
    end
  end
end
