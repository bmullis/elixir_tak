defmodule ElixirTAK.Video.HLSWorkerTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.Video.{HLSSupervisor, HLSWorker}

  @hls_dir "data/hls_test"

  setup do
    # Use a test-specific HLS directory
    original_config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])

    Application.put_env(:elixir_tak, ElixirTAK.Video.HLS,
      Keyword.merge(original_config, hls_dir: @hls_dir, enabled: true)
    )

    on_exit(fn ->
      Application.put_env(:elixir_tak, ElixirTAK.Video.HLS, original_config)
      File.rm_rf(@hls_dir)
    end)

    :ok
  end

  describe "child_spec/1" do
    test "builds a valid child spec" do
      spec = HLSWorker.child_spec(%{uid: "test-1", url: "rtsp://example.com/stream", protocol: "rtsp"})
      assert spec.id == {HLSWorker, "test-1"}
      assert spec.restart == :transient
    end
  end

  describe "status/1" do
    test "returns :not_running for unknown uid" do
      assert HLSWorker.status("nonexistent") == :not_running
    end
  end

  describe "HLSSupervisor" do
    test "worker_running? returns false for unknown uid" do
      refute HLSSupervisor.worker_running?("nonexistent")
    end

    test "stop_worker returns :ok for unknown uid" do
      assert HLSSupervisor.stop_worker("nonexistent") == :ok
    end
  end

  describe "HLS URL helpers" do
    test "hls_url/1 returns correct path" do
      assert ElixirTAK.VideoRegistry.hls_url("video-abc123") ==
               "/Marti/api/video/video-abc123/hls/index.m3u8"
    end

    test "hls_available?/1 returns false when no segments exist" do
      refute ElixirTAK.VideoRegistry.hls_available?("nonexistent")
    end

    test "hls_available?/1 returns true when index exists" do
      uid = "hls-test-available"
      dir = Path.join(@hls_dir, uid)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "index.m3u8"), "#EXTM3U\n")

      assert ElixirTAK.VideoRegistry.hls_available?(uid)
    end
  end

  describe "worker lifecycle" do
    @tag :ffmpeg
    test "starts and stops a worker via supervisor" do
      # This test requires ffmpeg to be installed
      case System.find_executable("ffmpeg") do
        nil ->
          # Skip if ffmpeg not available
          :ok

        _path ->
          attrs = %{
            uid: "test-lifecycle",
            url: "rtsp://invalid.example.com/stream",
            protocol: "rtsp"
          }

          # Start worker
          {:ok, pid} = HLSSupervisor.start_worker(attrs)
          assert Process.alive?(pid)
          assert HLSSupervisor.worker_running?("test-lifecycle")

          # Status should be starting
          status = HLSWorker.status("test-lifecycle")
          assert status in [:starting, :error, :restarting]

          # Stop worker
          HLSSupervisor.stop_worker("test-lifecycle")
          refute HLSSupervisor.worker_running?("test-lifecycle")
      end
    end
  end
end
