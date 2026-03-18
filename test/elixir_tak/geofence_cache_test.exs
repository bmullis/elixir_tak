defmodule ElixirTAK.GeofenceCacheTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.GeofenceCache
  alias ElixirTAK.Protocol.CotEvent

  setup do
    :ets.delete_all_objects(:geofence_cache)
    :ok
  end

  test "stores and retrieves a geofence event" do
    event = build_geofence("GF-1", "Restricted Zone", 33.49, -111.93)
    GeofenceCache.put(event)

    assert [returned] = GeofenceCache.get_all()
    assert returned.uid == "GF-1"
  end

  test "updates existing geofence with same UID" do
    event1 = build_geofence("GF-1", "Zone A", 33.49, -111.93)
    event2 = build_geofence("GF-1", "Zone B", 33.50, -111.94)

    GeofenceCache.put(event1)
    GeofenceCache.put(event2)

    assert [returned] = GeofenceCache.get_all()
    assert returned.detail.callsign == "Zone B"
  end

  test "deletes a geofence by UID" do
    GeofenceCache.put(build_geofence("GF-1", "A", 33.49, -111.93))
    GeofenceCache.put(build_geofence("GF-2", "B", 33.50, -111.94))

    GeofenceCache.delete("GF-1")

    geofences = GeofenceCache.get_all()
    assert length(geofences) == 1
    assert hd(geofences).uid == "GF-2"
  end

  test "delete(nil) is a no-op" do
    assert GeofenceCache.delete(nil) == :ok
  end

  test "get_all returns stale geofences (not filtered)" do
    stale_event = build_geofence("GF-STALE", "Old Fence", 33.49, -111.93, stale_seconds: -60)
    GeofenceCache.put(stale_event)

    geofences = GeofenceCache.get_all()
    assert length(geofences) == 1
    assert CotEvent.stale?(hd(geofences))
  end

  test "count returns correct number" do
    assert GeofenceCache.count() == 0

    GeofenceCache.put(build_geofence("GF-1", "A", 33.49, -111.93))
    assert GeofenceCache.count() == 1

    GeofenceCache.put(build_geofence("GF-2", "B", 33.50, -111.94))
    assert GeofenceCache.count() == 2
  end

  test "put accepts optional group" do
    event = build_geofence("GF-1", "A", 33.49, -111.93)
    assert GeofenceCache.put(event, "Cyan") == :ok

    assert [returned] = GeofenceCache.get_all()
    assert returned.uid == "GF-1"
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_geofence(uid, callsign, lat, lon, opts \\ []) do
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
        "<detail><contact callsign=\"#{callsign}\"/><link point=\"#{lat},#{lon}\"/><__geofence trigger=\"Entry\" monitorType=\"TAKUsers\"/></detail>"
    }
  end
end
