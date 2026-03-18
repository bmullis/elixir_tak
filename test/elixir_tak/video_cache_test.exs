defmodule ElixirTAK.VideoCacheTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.VideoCache
  alias ElixirTAK.Protocol.CotEvent

  setup do
    :ets.delete_all_objects(:video_cache)
    :ok
  end

  test "stores and retrieves a video feed event" do
    event = build_video("vid-1", "Camera 1", 33.49, -111.93)
    VideoCache.put(event)

    assert [returned] = VideoCache.get_all()
    assert returned.uid == "vid-1"
  end

  test "updates existing entry with same UID" do
    event1 = build_video("vid-1", "Camera 1", 33.49, -111.93)
    event2 = build_video("vid-1", "Camera Moved", 33.50, -111.94)

    VideoCache.put(event1)
    VideoCache.put(event2)

    assert [returned] = VideoCache.get_all()
    assert returned.point.lat == 33.50
  end

  test "deletes a video feed by UID" do
    VideoCache.put(build_video("vid-1", "A", 33.49, -111.93))
    VideoCache.put(build_video("vid-2", "B", 33.50, -111.94))

    VideoCache.delete("vid-1")

    feeds = VideoCache.get_all()
    assert length(feeds) == 1
    assert hd(feeds).uid == "vid-2"
  end

  test "delete(nil) is a no-op" do
    assert VideoCache.delete(nil) == :ok
  end

  test "get_all filters out stale events" do
    stale_event = build_video("vid-stale", "Old Feed", 33.49, -111.93, stale_seconds: -60)
    VideoCache.put(stale_event)

    assert VideoCache.get_all() == []
  end

  test "count returns correct number" do
    assert VideoCache.count() == 0

    VideoCache.put(build_video("vid-1", "A", 33.49, -111.93))
    assert VideoCache.count() == 1

    VideoCache.put(build_video("vid-2", "B", 33.50, -111.94))
    assert VideoCache.count() == 2
  end

  test "put accepts optional group" do
    event = build_video("vid-1", "A", 33.49, -111.93)
    assert VideoCache.put(event, "Cyan") == :ok

    assert [returned] = VideoCache.get_all()
    assert returned.uid == "vid-1"
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_video(uid, alias_str, lat, lon, opts \\ []) do
    now = DateTime.utc_now()
    stale_seconds = Keyword.get(opts, :stale_seconds, 300)
    stale = DateTime.add(now, stale_seconds, :second)

    %CotEvent{
      uid: uid,
      type: "b-i-v",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil},
      detail: nil,
      raw_detail:
        "<detail><__video url=\"rtsp://example.local/live\" protocol=\"rtsp\"/><contact callsign=\"#{alias_str}\"/></detail>"
    }
  end
end
