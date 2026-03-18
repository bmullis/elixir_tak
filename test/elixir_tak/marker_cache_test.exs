defmodule ElixirTAK.MarkerCacheTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.MarkerCache
  alias ElixirTAK.Protocol.CotEvent

  setup do
    :ets.delete_all_objects(:marker_cache)
    :ok
  end

  test "stores and retrieves a marker event" do
    event = build_marker("MKR-1", "Checkpoint", 33.49, -111.93)
    MarkerCache.put(event)

    assert [returned] = MarkerCache.get_all()
    assert returned.uid == "MKR-1"
  end

  test "updates existing marker with same UID" do
    event1 = build_marker("MKR-1", "Checkpoint", 33.49, -111.93)
    event2 = build_marker("MKR-1", "Checkpoint Moved", 33.50, -111.94)

    MarkerCache.put(event1)
    MarkerCache.put(event2)

    assert [returned] = MarkerCache.get_all()
    assert returned.detail.callsign == "Checkpoint Moved"
    assert returned.point.lat == 33.50
  end

  test "deletes a marker by UID" do
    MarkerCache.put(build_marker("MKR-1", "A", 33.49, -111.93))
    MarkerCache.put(build_marker("MKR-2", "B", 33.50, -111.94))

    MarkerCache.delete("MKR-1")

    markers = MarkerCache.get_all()
    assert length(markers) == 1
    assert hd(markers).uid == "MKR-2"
  end

  test "delete(nil) is a no-op" do
    assert MarkerCache.delete(nil) == :ok
  end

  test "get_all returns stale markers (not filtered)" do
    stale_event = build_marker("MKR-STALE", "Old Point", 33.49, -111.93, stale_seconds: -60)
    MarkerCache.put(stale_event)

    markers = MarkerCache.get_all()
    assert length(markers) == 1
    assert CotEvent.stale?(hd(markers))
  end

  test "count returns correct number" do
    assert MarkerCache.count() == 0

    MarkerCache.put(build_marker("MKR-1", "A", 33.49, -111.93))
    assert MarkerCache.count() == 1

    MarkerCache.put(build_marker("MKR-2", "B", 33.50, -111.94))
    assert MarkerCache.count() == 2
  end

  test "put accepts optional group" do
    event = build_marker("MKR-1", "A", 33.49, -111.93)
    assert MarkerCache.put(event, "Cyan") == :ok

    assert [returned] = MarkerCache.get_all()
    assert returned.uid == "MKR-1"
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_marker(uid, callsign, lat, lon, opts \\ []) do
    now = DateTime.utc_now()
    stale_seconds = Keyword.get(opts, :stale_seconds, 86_400)
    stale = DateTime.add(now, stale_seconds, :second)

    %CotEvent{
      uid: uid,
      type: "b-m-p-s-p-i",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: callsign, group: nil, track: nil},
      raw_detail:
        "<detail><contact callsign=\"#{callsign}\"/><remarks>Test marker</remarks></detail>"
    }
  end
end
