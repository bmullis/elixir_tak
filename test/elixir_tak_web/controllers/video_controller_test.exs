defmodule ElixirTAKWeb.VideoControllerTest do
  use ElixirTAKWeb.ConnCase

  alias ElixirTAK.VideoRegistry

  setup do
    :ets.delete_all_objects(:video_registry)
    :ok
  end

  describe "GET /api/video" do
    test "returns empty list when no streams", %{conn: conn} do
      conn = get(conn, "/api/video")
      body = json_response(conn, 200)
      assert body["count"] == 0
      assert body["streams"] == []
    end

    test "returns all registered streams", %{conn: conn} do
      VideoRegistry.register(%{url: "rtsp://a", alias: "Cam A"})
      VideoRegistry.register(%{url: "rtmp://b", alias: "Cam B"})

      conn = get(conn, "/api/video")
      body = json_response(conn, 200)
      assert body["count"] == 2
    end
  end

  describe "GET /api/video/:uid" do
    test "returns a stream by uid", %{conn: conn} do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam", alias: "Gate Cam"})

      conn = get(conn, "/api/video/#{uid}")
      body = json_response(conn, 200)
      assert body["stream"]["uid"] == uid
      assert body["stream"]["alias"] == "Gate Cam"
      assert body["stream"]["protocol"] == "rtsp"
    end

    test "returns 404 for missing stream", %{conn: conn} do
      conn = get(conn, "/api/video/nonexistent")
      assert json_response(conn, 404)["error"] == "stream not found"
    end
  end

  describe "POST /api/video" do
    test "creates a stream", %{conn: conn} do
      conn =
        post(conn, "/api/video", %{
          "url" => "rtsp://cam.local/live",
          "alias" => "Front Gate",
          "lat" => "33.45",
          "lon" => "-112.07",
          "broadcast" => false
        })

      body = json_response(conn, 201)
      assert body["status"] == "registered"
      assert is_binary(body["uid"])
    end

    test "creates with custom uid", %{conn: conn} do
      conn =
        post(conn, "/api/video", %{
          "uid" => "my-cam-1",
          "url" => "rtsp://cam.local/live",
          "broadcast" => false
        })

      body = json_response(conn, 201)
      assert body["uid"] == "my-cam-1"
    end

    test "returns 400 when url is missing", %{conn: conn} do
      conn = post(conn, "/api/video", %{"alias" => "No URL"})
      assert json_response(conn, 400)["error"] == "url is required"
    end
  end

  describe "PUT /api/video/:uid" do
    test "updates a stream", %{conn: conn} do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://old", alias: "Old"})

      conn =
        put(conn, "/api/video/#{uid}", %{
          "alias" => "Updated",
          "url" => "rtsp://new",
          "broadcast" => false
        })

      body = json_response(conn, 200)
      assert body["stream"]["alias"] == "Updated"
      assert body["stream"]["url"] == "rtsp://new"
    end

    test "returns 404 for missing stream", %{conn: conn} do
      conn = put(conn, "/api/video/nonexistent", %{"alias" => "X"})
      assert json_response(conn, 404)["error"] == "stream not found"
    end
  end

  describe "DELETE /api/video/:uid" do
    test "deletes a stream", %{conn: conn} do
      {:ok, uid} = VideoRegistry.register(%{url: "rtsp://cam"})

      conn = delete(conn, "/api/video/#{uid}")
      body = json_response(conn, 200)
      assert body["status"] == "deleted"
      assert body["uid"] == uid

      assert {:error, :not_found} = VideoRegistry.get(uid)
    end

    test "returns 404 for missing stream", %{conn: conn} do
      conn = delete(conn, "/api/video/nonexistent")
      assert json_response(conn, 404)["error"] == "stream not found"
    end
  end

  describe "GET /Marti/api/video/:uid/hls/:filename" do
    @hls_dir "data/hls_test_ctrl"

    setup do
      original_config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])

      Application.put_env(
        :elixir_tak,
        ElixirTAK.Video.HLS,
        Keyword.merge(original_config, hls_dir: @hls_dir)
      )

      on_exit(fn ->
        Application.put_env(:elixir_tak, ElixirTAK.Video.HLS, original_config)
        File.rm_rf(@hls_dir)
      end)
    end

    test "serves m3u8 playlist", %{conn: conn} do
      uid = "hls-serve-test"
      dir = Path.join(@hls_dir, uid)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "index.m3u8"), "#EXTM3U\n#EXT-X-VERSION:3\n")

      conn = get(conn, "/Marti/api/video/#{uid}/hls/index.m3u8")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "mpegurl"
    end

    test "serves ts segment", %{conn: conn} do
      uid = "hls-ts-test"
      dir = Path.join(@hls_dir, uid)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "seg_00001.ts"), "fake-ts-data")

      conn = get(conn, "/Marti/api/video/#{uid}/hls/seg_00001.ts")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "MP2T"
    end

    test "returns 404 for missing file", %{conn: conn} do
      conn = get(conn, "/Marti/api/video/nonexistent/hls/index.m3u8")
      assert json_response(conn, 404)["error"] == "not found"
    end

    test "rejects directory traversal", %{conn: conn} do
      conn = get(conn, "/Marti/api/video/test/hls/..%2F..%2Fetc%2Fpasswd")
      assert conn.status in [400, 404]
    end
  end

  describe "GET /Marti/api/video/:uid/snapshot/latest" do
    @snapshot_dir "data/snapshots_test"

    setup do
      original_config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])

      Application.put_env(
        :elixir_tak,
        ElixirTAK.Video.HLS,
        Keyword.merge(original_config, snapshot_dir: @snapshot_dir)
      )

      on_exit(fn ->
        Application.put_env(:elixir_tak, ElixirTAK.Video.HLS, original_config)
        File.rm_rf(@snapshot_dir)
      end)
    end

    test "serves latest snapshot", %{conn: conn} do
      uid = "snap-test"
      dir = Path.join(@snapshot_dir, uid)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "1234567890.jpg"), "fake-jpeg")

      conn = get(conn, "/Marti/api/video/#{uid}/snapshot/latest")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "jpeg"
    end

    test "returns 404 when no snapshot exists", %{conn: conn} do
      conn = get(conn, "/Marti/api/video/no-snap/snapshot/latest")
      assert json_response(conn, 404)["error"] == "no snapshot available"
    end
  end
end
