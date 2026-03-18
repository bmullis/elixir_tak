defmodule ElixirTAK.Protocol.CotParserTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, CotParser}

  @full_event """
  <event uid="ANDROID-abc123" type="a-f-G-U-C" how="m-g"
         time="2024-01-15T12:00:00Z" start="2024-01-15T12:00:00Z"
         stale="2024-01-15T12:05:00Z" version="2.0">
    <point lat="38.8977" lon="-77.0365" hae="10.5" ce="9999999" le="9999999"/>
    <detail>
      <contact callsign="ALPHA-1"/>
      <__group name="Cyan" role="Team Lead"/>
      <track speed="2.5" course="180.0"/>
    </detail>
  </event>
  """

  @minimal_event """
  <event uid="test-1" type="a-f-G">
    <point lat="0.0" lon="0.0" hae="0.0" ce="0.0" le="0.0"/>
  </event>
  """

  describe "parse/1" do
    test "parses a full CoT event with all fields" do
      assert {:ok, %CotEvent{} = event} = CotParser.parse(@full_event)

      assert event.uid == "ANDROID-abc123"
      assert event.type == "a-f-G-U-C"
      assert event.how == "m-g"
      assert event.time == ~U[2024-01-15 12:00:00Z]
      assert event.start == ~U[2024-01-15 12:00:00Z]
      assert event.stale == ~U[2024-01-15 12:05:00Z]
    end

    test "parses point attributes" do
      {:ok, event} = CotParser.parse(@full_event)

      assert event.point == %{
               lat: 38.8977,
               lon: -77.0365,
               hae: 10.5,
               ce: nil,
               le: nil
             }
    end

    test "parses detail with callsign, group, and track" do
      {:ok, event} = CotParser.parse(@full_event)

      assert event.detail.callsign == "ALPHA-1"
      assert event.detail.group == %{name: "Cyan", role: "Team Lead"}
      assert event.detail.track == %{speed: 2.5, course: 180.0}
    end

    test "parses a minimal event with no detail" do
      {:ok, event} = CotParser.parse(@minimal_event)

      assert event.uid == "test-1"
      assert event.type == "a-f-G"
      assert event.how == nil
      assert event.time == nil
      assert event.detail == nil
    end

    test "handles detail with missing optional children" do
      xml = """
      <event uid="test-2" type="a-f-G">
        <point lat="1.0" lon="2.0" hae="0.0" ce="0.0" le="0.0"/>
        <detail>
          <contact callsign="BRAVO"/>
        </detail>
      </event>
      """

      {:ok, event} = CotParser.parse(xml)

      assert event.detail.callsign == "BRAVO"
      assert event.detail.group == nil
      assert event.detail.track == nil
    end

    test "returns error for non-event XML" do
      assert {:error, :not_a_cot_event} = CotParser.parse("<message><body/></message>")
    end

    test "returns error for invalid XML" do
      assert {:error, :xml_parse_error} = CotParser.parse("not xml at all <<<")
    end

    test "returns error when point is missing" do
      xml = """
      <event uid="no-point" type="a-f-G">
        <detail/>
      </event>
      """

      assert {:error, :missing_point} = CotParser.parse(xml)
    end

    test "returns error when required attrs are missing" do
      xml = """
      <event>
        <point lat="0" lon="0" hae="0" ce="0" le="0"/>
      </event>
      """

      assert {:error, :missing_required_attrs} = CotParser.parse(xml)
    end
  end

  describe "raw_detail passthrough" do
    @atak_event """
    <event uid="ANDROID-abc123" type="a-f-G-U-C" how="m-g"
           time="2024-01-15T12:00:00Z" start="2024-01-15T12:00:00Z"
           stale="2024-01-15T12:05:00Z" version="2.0">
      <point lat="38.8977" lon="-77.0365" hae="10.5" ce="9999999" le="9999999"/>
      <detail>
        <contact callsign="ALPHA-1"/>
        <__group name="Cyan" role="Team Lead"/>
        <track speed="2.5" course="180.0"/>
        <takv device="Samsung Galaxy S21" os="Android" platform="ATAK-CIV" version="4.8.1"/>
        <status battery="87"/>
        <precisionlocation geopointsrc="GPS" altsrc="GPS"/>
        <remarks>On patrol near checkpoint 4</remarks>
        <uid Droid="ALPHA-1"/>
      </detail>
    </event>
    """

    test "still extracts structured detail fields" do
      {:ok, event} = CotParser.parse(@atak_event)

      assert event.detail.callsign == "ALPHA-1"
      assert event.detail.group == %{name: "Cyan", role: "Team Lead"}
      assert event.detail.track == %{speed: 2.5, course: 180.0}
    end

    test "captures raw_detail with all children" do
      {:ok, event} = CotParser.parse(@atak_event)

      assert is_binary(event.raw_detail)
      assert event.raw_detail =~ "<detail>"
      assert event.raw_detail =~ "</detail>"
      assert event.raw_detail =~ "takv"
      assert event.raw_detail =~ ~s(battery="87")
      assert event.raw_detail =~ "precisionlocation"
      assert event.raw_detail =~ "On patrol near checkpoint 4"
      assert event.raw_detail =~ ~s(Droid="ALPHA-1")
    end

    test "raw_detail is nil when no detail element" do
      {:ok, event} = CotParser.parse(@minimal_event)

      assert event.detail == nil
      assert event.raw_detail == nil
    end

    test "captures raw_detail for minimal detail" do
      xml = """
      <event uid="test-2" type="a-f-G">
        <point lat="1.0" lon="2.0" hae="0.0" ce="0.0" le="0.0"/>
        <detail>
          <contact callsign="BRAVO"/>
        </detail>
      </event>
      """

      {:ok, event} = CotParser.parse(xml)

      assert event.detail.callsign == "BRAVO"
      assert is_binary(event.raw_detail)
      assert event.raw_detail =~ ~s(callsign="BRAVO")
    end
  end
end
