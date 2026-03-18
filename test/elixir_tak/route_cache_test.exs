defmodule ElixirTAK.RouteCacheTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.RouteCache
  alias ElixirTAK.Protocol.CotEvent

  setup do
    :ets.delete_all_objects(:route_cache)
    :ok
  end

  test "stores and retrieves a route event" do
    event = build_route("RT-1", "Route ALPHA")
    RouteCache.put(event)

    assert [returned] = RouteCache.get_all()
    assert returned.uid == "RT-1"
  end

  test "updates existing route with same UID" do
    event1 = build_route("RT-1", "Route A")
    event2 = build_route("RT-1", "Route B")

    RouteCache.put(event1)
    RouteCache.put(event2)

    assert [returned] = RouteCache.get_all()
    assert returned.detail.callsign == "Route B"
  end

  test "deletes a route by UID" do
    RouteCache.put(build_route("RT-1", "A"))
    RouteCache.put(build_route("RT-2", "B"))

    RouteCache.delete("RT-1")

    routes = RouteCache.get_all()
    assert length(routes) == 1
    assert hd(routes).uid == "RT-2"
  end

  test "delete(nil) is a no-op" do
    assert RouteCache.delete(nil) == :ok
  end

  test "get_all returns stale routes (not filtered)" do
    stale_event = build_route("RT-STALE", "Old Route", stale_seconds: -60)
    RouteCache.put(stale_event)

    routes = RouteCache.get_all()
    assert length(routes) == 1
    assert CotEvent.stale?(hd(routes))
  end

  test "count returns correct number" do
    assert RouteCache.count() == 0

    RouteCache.put(build_route("RT-1", "A"))
    assert RouteCache.count() == 1

    RouteCache.put(build_route("RT-2", "B"))
    assert RouteCache.count() == 2
  end

  test "put accepts optional group" do
    event = build_route("RT-1", "A")
    assert RouteCache.put(event, "Cyan") == :ok

    assert [returned] = RouteCache.get_all()
    assert returned.uid == "RT-1"
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_route(uid, callsign, opts \\ []) do
    now = DateTime.utc_now()
    stale_seconds = Keyword.get(opts, :stale_seconds, 86_400)
    stale = DateTime.add(now, stale_seconds, :second)

    raw_detail = """
    <detail>\
    <contact callsign="#{callsign}"/>\
    <link uid="wp0" type="b-m-p-w" relation="c" point="33.49,-111.93"/>\
    <link uid="wp1" type="b-m-p-w" relation="c" point="33.50,-111.92"/>\
    </detail>\
    """

    %CotEvent{
      uid: uid,
      type: "b-m-r",
      how: "h-e",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: callsign, group: nil, track: nil},
      raw_detail: raw_detail
    }
  end
end
