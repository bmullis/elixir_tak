defmodule ElixirTAK.History.WriterTest do
  use ElixirTAK.DataCase, async: false

  alias ElixirTAK.History.{EventRecord, Writer}
  alias ElixirTAK.Protocol.CotEvent

  @sample_xml ~s(<event version="2.0" uid="test-1" type="a-f-G-U-C" how="m-g" time="2025-01-01T00:00:00Z" start="2025-01-01T00:00:00Z" stale="2025-01-01T00:10:00Z"><point lat="33.5" lon="-111.9" hae="0" ce="9999999" le="9999999"/><detail><contact callsign="TestUser"/></detail></event>)

  setup do
    # Drain any stale events from the Writer's buffer
    send(Writer, :flush)
    Process.sleep(50)
    # Clean the table so each test starts fresh
    Repo.delete_all(EventRecord)
    :ok
  end

  defp sample_event do
    %CotEvent{
      uid: "test-1",
      type: "a-f-G-U-C",
      how: "m-g",
      time: ~U[2025-01-01 00:00:00Z],
      start: ~U[2025-01-01 00:00:00Z],
      stale: ~U[2025-01-01 00:10:00Z],
      point: %{lat: 33.5, lon: -111.9, hae: 0.0, ce: nil, le: nil},
      detail: %{
        callsign: "TestUser",
        group: %{name: "Cyan", role: "Team Member"},
        track: %{speed: 5.0, course: 90.0}
      },
      raw_detail: nil
    }
  end

  test "record/3 persists an event after flush" do
    Writer.record(sample_event(), @sample_xml, "Cyan")

    # Trigger flush by sending the timer message
    send(Writer, :flush)
    # Give the flush a moment to complete
    Process.sleep(50)

    records = Repo.all(EventRecord)
    assert length(records) == 1

    record = hd(records)
    assert record.uid == "test-1"
    assert record.type == "a-f-G-U-C"
    assert record.callsign == "TestUser"
    assert record.group_name == "Cyan"
    assert record.lat == 33.5
    assert record.lon == -111.9
    assert record.speed == 5.0
    assert record.course == 90.0
    assert record.raw_xml == @sample_xml
  end

  test "batch flushing persists all events" do
    for i <- 1..50 do
      event = %{sample_event() | uid: "batch-#{i}"}
      Writer.record(event, @sample_xml, "Cyan")
    end

    send(Writer, :flush)
    Process.sleep(50)

    assert Repo.aggregate(EventRecord, :count) == 50
  end

  test "raw_xml is stored verbatim" do
    xml =
      ~s(<event version="2.0" uid="raw-test" type="a-f-G" how="m-g" time="2025-01-01T00:00:00Z" start="2025-01-01T00:00:00Z" stale="2025-01-01T00:10:00Z"><point lat="1" lon="2" hae="0" ce="0" le="0"/><detail><contact callsign="Raw"/><__group name="Blue" role="HQ"/><takv version="4.10" platform="ATAK"/></detail></event>)

    Writer.record(sample_event(), xml, "Blue")
    send(Writer, :flush)
    Process.sleep(50)

    record = Repo.one!(from(e in EventRecord, where: e.uid == "test-1"))
    assert record.raw_xml == xml
  end
end
