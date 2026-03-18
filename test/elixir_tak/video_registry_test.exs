defmodule ElixirTAK.VideoRegistryTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.VideoRegistry

  setup do
    :ets.delete_all_objects(:video_registry)
    :ets.delete_all_objects(:video_cache)
    :ok
  end

  describe "register/1" do
    test "registers a stream and returns a uid" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam1.local/live"})
      assert is_binary(uid)
      assert String.starts_with?(uid, "video-")
    end

    test "uses provided uid" do
      {:ok, uid} = VideoRegistry.register(%{uid: "my-cam", url: "rtsp://cam.local/live"})
      assert uid == "my-cam"
    end

    test "detects protocol from url" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam.local/live"})
      {:ok, stream} = VideoRegistry.get(uid)
      assert stream.protocol == "rtsp"
    end

    test "stores lat/lon/hae" do
      {:ok, uid} =
        VideoRegistry.register(%{
          url: "rtmp://stream.local/live",
          lat: 33.4484,
          lon: -112.074,
          hae: 331.0
        })

      {:ok, stream} = VideoRegistry.get(uid)
      assert_in_delta stream.lat, 33.4484, 0.001
      assert_in_delta stream.lon, -112.074, 0.001
      assert_in_delta stream.hae, 331.0, 0.1
    end

    test "parses string lat/lon" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://x", lat: "33.5", lon: "-112.0"})
      {:ok, stream} = VideoRegistry.get(uid)
      assert_in_delta stream.lat, 33.5, 0.01
      assert_in_delta stream.lon, -112.0, 0.01
    end
  end

  describe "list/0" do
    test "returns all streams" do
      VideoRegistry.register(%{url: "rtsp://a"})
      VideoRegistry.register(%{url: "rtsp://b"})
      assert length(VideoRegistry.list()) == 2
    end

    test "returns empty list when no streams" do
      assert VideoRegistry.list() == []
    end
  end

  describe "get/1" do
    test "returns stream by uid" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam", alias: "Front Gate"})
      {:ok, stream} = VideoRegistry.get(uid)
      assert stream.alias == "Front Gate"
      assert stream.url == "rtsp://cam"
    end

    test "returns error for missing uid" do
      assert {:error, :not_found} = VideoRegistry.get("nonexistent")
    end
  end

  describe "update/2" do
    test "updates stream metadata" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://old", alias: "Old Name"})
      {:ok, updated} = VideoRegistry.update(uid, %{alias: "New Name", url: "rtsp://new"})
      assert updated.alias == "New Name"
      assert updated.url == "rtsp://new"
      assert updated.protocol == "rtsp"
    end

    test "partial update preserves existing fields" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam", alias: "Cam", lat: 33.0})
      {:ok, updated} = VideoRegistry.update(uid, %{alias: "Updated Cam"})
      assert updated.alias == "Updated Cam"
      assert updated.url == "rtsp://cam"
      assert_in_delta updated.lat, 33.0, 0.01
    end

    test "returns error for missing uid" do
      assert {:error, :not_found} = VideoRegistry.update("nope", %{alias: "X"})
    end
  end

  describe "delete/1" do
    test "removes a stream" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam"})
      assert :ok = VideoRegistry.delete(uid)
      assert {:error, :not_found} = VideoRegistry.get(uid)
    end

    test "returns error for missing uid" do
      assert {:error, :not_found} = VideoRegistry.delete("nope")
    end
  end

  describe "broadcast_cot/1" do
    test "broadcasts a b-i-v CoT event" do
      Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")

      {:ok, uid} =
        VideoRegistry.register(%{
          url: "rtsp://cam.local/live",
          alias: "Test Cam",
          lat: 33.45,
          lon: -112.07
        })

      VideoRegistry.broadcast_cot(uid)

      assert_receive {:cot_broadcast, ^uid, event, nil}
      assert event.type == "b-i-v"
      assert event.uid == uid
      assert_in_delta event.point.lat, 33.45, 0.01
      assert_in_delta event.point.lon, -112.07, 0.01
      assert event.raw_detail =~ "rtsp://cam.local/live"
      assert event.raw_detail =~ "Test Cam"
    end

    test "returns error for missing stream" do
      assert {:error, :not_found} = VideoRegistry.broadcast_cot("nonexistent")
    end

    test "includes connectionEntry element in CoT detail" do
      Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")

      {:ok, uid} =
        VideoRegistry.register(%{
          url: "rtsp://cam.local:8554/live",
          alias: "Gate Cam",
          lat: 33.45,
          lon: -112.07
        })

      VideoRegistry.broadcast_cot(uid)

      assert_receive {:cot_broadcast, ^uid, event, nil}
      assert event.raw_detail =~ "connectionEntry"
      assert event.raw_detail =~ ~s(protocol="rtsp")
      assert event.raw_detail =~ ~s(address="cam.local")
      assert event.raw_detail =~ ~s(port="8554")
      assert event.raw_detail =~ ~s(alias="Gate Cam")
    end
  end

  describe "video cache integration" do
    test "register/1 populates VideoCache" do
      {:ok, uid} =
        VideoRegistry.register(%{url: "rtsp://cam.local/live", alias: "Cam 1", lat: 33.0, lon: -112.0})

      feeds = ElixirTAK.VideoCache.get_all()
      assert length(feeds) == 1
      assert hd(feeds).uid == uid
      assert hd(feeds).type == "b-i-v"
    end

    test "update/2 refreshes VideoCache entry" do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam.local/live", alias: "Old"})
      VideoRegistry.update(uid, %{alias: "New"})

      feeds = ElixirTAK.VideoCache.get_all()
      assert length(feeds) == 1
      assert hd(feeds).raw_detail =~ "New"
    end

    test "delete/1 removes from VideoCache and broadcasts delete CoT" do
      Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")

      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam.local/live"})
      # drain the register broadcast from VideoCache.put
      assert ElixirTAK.VideoCache.count() == 1

      VideoRegistry.delete(uid)

      assert ElixirTAK.VideoCache.count() == 0
      assert_receive {:cot_broadcast, ^uid, event, nil}
      assert event.type == "t-x-d-d"
      assert event.raw_detail =~ uid
    end
  end
end
