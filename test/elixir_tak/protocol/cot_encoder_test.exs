defmodule ElixirTAK.Protocol.CotEncoderTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEncoder, CotEvent, CotParser}

  @full_event %CotEvent{
    uid: "ANDROID-abc123",
    type: "a-f-G-U-C",
    how: "m-g",
    time: ~U[2024-01-15 12:00:00Z],
    start: ~U[2024-01-15 12:00:00Z],
    stale: ~U[2024-01-15 12:05:00Z],
    point: %{lat: 38.8977, lon: -77.0365, hae: 10.5, ce: nil, le: nil},
    detail: %{
      callsign: "ALPHA-1",
      group: %{name: "Cyan", role: "Team Lead"},
      track: %{speed: 2.5, course: 180.0}
    }
  }

  @minimal_event %CotEvent{
    uid: "test-1",
    type: "a-f-G",
    point: %{lat: 0.0, lon: 0.0, hae: 0.0, ce: 0.0, le: 0.0}
  }

  describe "encode/1" do
    test "encodes a full event to valid XML" do
      xml = @full_event |> CotEncoder.encode() |> IO.iodata_to_binary()

      assert xml =~ ~s(uid="ANDROID-abc123")
      assert xml =~ ~s(type="a-f-G-U-C")
      assert xml =~ ~s(how="m-g")
      assert xml =~ ~s(version="2.0")
      assert xml =~ ~s(lat="38.8977")
      assert xml =~ ~s(lon="-77.0365")
      assert xml =~ ~s(callsign="ALPHA-1")
      assert xml =~ ~s(name="Cyan")
      assert xml =~ ~s(role="Team Lead")
      assert xml =~ ~s(speed="2.5")
      assert xml =~ ~s(course="180.0")
    end

    test "encodes a minimal event without detail" do
      xml = @minimal_event |> CotEncoder.encode() |> IO.iodata_to_binary()

      assert xml =~ ~s(uid="test-1")
      assert xml =~ ~s(type="a-f-G")
      refute xml =~ "<detail>"
      refute xml =~ ~s(how=")
    end

    test "skips nil attributes" do
      xml = @minimal_event |> CotEncoder.encode() |> IO.iodata_to_binary()

      refute xml =~ ~s(how=")
      refute xml =~ ~s(time=")
      refute xml =~ ~s(start=")
      refute xml =~ ~s(stale=")
    end

    test "encodes nil ce/le/hae as sentinel 9999999.0" do
      event = %CotEvent{
        uid: "test-sentinel",
        type: "a-f-G",
        point: %{lat: 1.0, lon: 2.0, hae: nil, ce: nil, le: nil}
      }

      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()

      assert xml =~ ~s(hae="9999999.0")
      assert xml =~ ~s(ce="9999999.0")
      assert xml =~ ~s(le="9999999.0")
    end

    test "returns iodata, not a binary" do
      result = CotEncoder.encode(@minimal_event)
      assert is_list(result)
    end

    test "round-trip: encode then parse recovers the same event" do
      xml = @full_event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)

      assert parsed.uid == @full_event.uid
      assert parsed.type == @full_event.type
      assert parsed.how == @full_event.how
      assert parsed.time == @full_event.time
      assert parsed.start == @full_event.start
      assert parsed.stale == @full_event.stale
      assert parsed.point == @full_event.point
      assert parsed.detail == @full_event.detail
    end

    test "round-trip: minimal event without detail" do
      xml = @minimal_event |> CotEncoder.encode() |> IO.iodata_to_binary()
      assert {:ok, parsed} = CotParser.parse(xml)

      assert parsed.uid == @minimal_event.uid
      assert parsed.type == @minimal_event.type
      assert parsed.point == @minimal_event.point
      assert parsed.detail == nil
    end
  end

  describe "raw_detail passthrough" do
    test "uses raw_detail verbatim when present" do
      raw = ~s(<detail><contact callsign="ALPHA-1"/><takv device="Phone" os="Android"/></detail>)

      event = %CotEvent{
        uid: "test-raw",
        type: "a-f-G",
        point: %{lat: 1.0, lon: 2.0, hae: nil, ce: nil, le: nil},
        detail: %{callsign: "ALPHA-1", group: nil, track: nil},
        raw_detail: raw
      }

      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()

      assert xml =~ ~s(<takv device="Phone" os="Android"/>)
      assert xml =~ ~s(callsign="ALPHA-1")
    end

    test "falls back to structured encoding when raw_detail is nil" do
      xml = @full_event |> CotEncoder.encode() |> IO.iodata_to_binary()

      assert xml =~ "<detail>"
      assert xml =~ ~s(callsign="ALPHA-1")
      assert xml =~ ~s(name="Cyan")
    end

    test "round-trip preserves extra detail elements" do
      input_xml = """
      <event uid="ANDROID-abc123" type="a-f-G-U-C" how="m-g"
             time="2024-01-15T12:00:00Z" start="2024-01-15T12:00:00Z"
             stale="2024-01-15T12:05:00Z" version="2.0">
        <point lat="38.8977" lon="-77.0365" hae="10.5" ce="9999999" le="9999999"/>
        <detail>
          <contact callsign="ALPHA-1"/>
          <__group name="Cyan" role="Team Lead"/>
          <track speed="2.5" course="180.0"/>
          <takv device="Phone" os="Android" platform="ATAK-CIV" version="4.8.1"/>
          <status battery="87"/>
          <remarks>Checkpoint 4</remarks>
        </detail>
      </event>
      """

      {:ok, parsed} = CotParser.parse(input_xml)
      re_encoded = parsed |> CotEncoder.encode() |> IO.iodata_to_binary()
      {:ok, re_parsed} = CotParser.parse(re_encoded)

      # Structured fields survive round-trip
      assert re_parsed.detail.callsign == "ALPHA-1"
      assert re_parsed.detail.group == %{name: "Cyan", role: "Team Lead"}
      assert re_parsed.detail.track == %{speed: 2.5, course: 180.0}

      # Extra detail elements survive round-trip
      assert re_encoded =~ "takv"
      assert re_encoded =~ ~s(battery="87")
      assert re_encoded =~ "Checkpoint 4"
    end
  end
end
