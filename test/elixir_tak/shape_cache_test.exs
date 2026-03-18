defmodule ElixirTAK.ShapeCacheTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.ShapeCache
  alias ElixirTAK.Protocol.CotEvent

  setup do
    :ets.delete_all_objects(:shape_cache)
    :ok
  end

  test "stores and retrieves a shape event" do
    event = build_shape("SHP-1", "Patrol Zone", 33.49, -111.93)
    ShapeCache.put(event)

    assert [returned] = ShapeCache.get_all()
    assert returned.uid == "SHP-1"
  end

  test "updates existing shape with same UID" do
    event1 = build_shape("SHP-1", "Zone A", 33.49, -111.93)
    event2 = build_shape("SHP-1", "Zone B", 33.50, -111.94)

    ShapeCache.put(event1)
    ShapeCache.put(event2)

    assert [returned] = ShapeCache.get_all()
    assert returned.detail.callsign == "Zone B"
  end

  test "deletes a shape by UID" do
    ShapeCache.put(build_shape("SHP-1", "A", 33.49, -111.93))
    ShapeCache.put(build_shape("SHP-2", "B", 33.50, -111.94))

    ShapeCache.delete("SHP-1")

    shapes = ShapeCache.get_all()
    assert length(shapes) == 1
    assert hd(shapes).uid == "SHP-2"
  end

  test "delete(nil) is a no-op" do
    assert ShapeCache.delete(nil) == :ok
  end

  test "get_all returns stale shapes (not filtered)" do
    stale_event = build_shape("SHP-STALE", "Old Zone", 33.49, -111.93, stale_seconds: -60)
    ShapeCache.put(stale_event)

    shapes = ShapeCache.get_all()
    assert length(shapes) == 1
    assert CotEvent.stale?(hd(shapes))
  end

  test "count returns correct number" do
    assert ShapeCache.count() == 0

    ShapeCache.put(build_shape("SHP-1", "A", 33.49, -111.93))
    assert ShapeCache.count() == 1

    ShapeCache.put(build_shape("SHP-2", "B", 33.50, -111.94))
    assert ShapeCache.count() == 2
  end

  test "put accepts optional group" do
    event = build_shape("SHP-1", "A", 33.49, -111.93)
    assert ShapeCache.put(event, "Cyan") == :ok

    assert [returned] = ShapeCache.get_all()
    assert returned.uid == "SHP-1"
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_shape(uid, callsign, lat, lon, opts \\ []) do
    now = DateTime.utc_now()
    stale_seconds = Keyword.get(opts, :stale_seconds, 86_400)
    stale = DateTime.add(now, stale_seconds, :second)

    %CotEvent{
      uid: uid,
      type: "u-d-p",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil},
      detail: %{callsign: callsign, group: nil, track: nil},
      raw_detail:
        "<detail><contact callsign=\"#{callsign}\"/><link point=\"#{lat},#{lon}\"/></detail>"
    }
  end
end
