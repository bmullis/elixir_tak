defmodule ElixirTAK.Video.HLSWorker do
  @moduledoc """
  GenServer wrapping an FFmpeg process that transcodes a video stream to HLS.

  Each worker manages a single FFmpeg Port that reads from a source URL
  (RTSP/RTMP) and writes HLS segments to `data/hls/<uid>/`. The segments
  are served by Phoenix for browser playback via hls.js.
  """

  use GenServer, restart: :transient

  require Logger

  @pubsub ElixirTAK.PubSub
  @max_restart_attempts 3
  @restart_backoff_ms 5_000

  # -- Public API ------------------------------------------------------------

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs,
      name: {:via, Registry, {ElixirTAK.Video.HLSRegistry, attrs.uid}}
    )
  end

  def child_spec(attrs) do
    %{
      id: {__MODULE__, attrs.uid},
      start: {__MODULE__, :start_link, [attrs]},
      restart: :transient,
      shutdown: 5_000
    }
  end

  @doc "Get the current status of an HLS worker."
  def status(uid) do
    case Registry.lookup(ElixirTAK.Video.HLSRegistry, uid) do
      [{pid, _}] -> GenServer.call(pid, :status)
      [] -> :not_running
    end
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(attrs) do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    hls_dir = config[:hls_dir] || "data/hls"
    output_dir = Path.join(hls_dir, attrs.uid)

    state = %{
      uid: attrs.uid,
      url: attrs.url,
      protocol: attrs.protocol,
      output_dir: output_dir,
      port: nil,
      os_pid: nil,
      status: :starting,
      restart_count: 0,
      config: config
    }

    {:ok, state, {:continue, :start_ffmpeg}}
  end

  @impl true
  def handle_continue(:start_ffmpeg, state) do
    case start_ffmpeg(state) do
      {:ok, new_state} ->
        broadcast_status(new_state.uid, :starting)
        schedule_ready_check(2_000)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("HLS worker #{state.uid}: failed to start FFmpeg: #{inspect(reason)}")
        broadcast_status(state.uid, :error)
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Log FFmpeg output at debug level
    for line <- String.split(to_string(data), "\n", trim: true) do
      Logger.debug("FFmpeg [#{state.uid}]: #{line}")
    end

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    Logger.info("HLS worker #{state.uid}: FFmpeg exited normally")
    broadcast_status(state.uid, :stopped)
    {:stop, :normal, %{state | port: nil, os_pid: nil}}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("HLS worker #{state.uid}: FFmpeg exited with code #{code}")

    if state.restart_count < @max_restart_attempts do
      Logger.info("HLS worker #{state.uid}: scheduling restart (attempt #{state.restart_count + 1}/#{@max_restart_attempts})")
      Process.send_after(self(), :restart_ffmpeg, @restart_backoff_ms)
      {:noreply, %{state | port: nil, os_pid: nil, status: :restarting, restart_count: state.restart_count + 1}}
    else
      Logger.error("HLS worker #{state.uid}: max restart attempts reached, giving up")
      broadcast_status(state.uid, :error)
      {:stop, :normal, %{state | port: nil, os_pid: nil, status: :error}}
    end
  end

  def handle_info(:restart_ffmpeg, state) do
    case start_ffmpeg(state) do
      {:ok, new_state} ->
        broadcast_status(new_state.uid, :starting)
        schedule_ready_check(3_000)
        {:noreply, new_state}

      {:error, _reason} ->
        broadcast_status(state.uid, :error)
        {:stop, :normal, state}
    end
  end

  def handle_info(:check_ready, state) do
    index_path = Path.join(state.output_dir, "index.m3u8")

    if File.exists?(index_path) do
      Logger.info("HLS worker #{state.uid}: stream ready")
      broadcast_status(state.uid, :ready)
      {:noreply, %{state | status: :ready}}
    else
      if state.status == :starting do
        # Check again in a bit
        schedule_ready_check(2_000)
      end

      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def terminate(_reason, state) do
    kill_ffmpeg(state)
    cleanup_segments(state.output_dir)
    :ok
  end

  # -- Private ---------------------------------------------------------------

  defp start_ffmpeg(state) do
    File.mkdir_p!(state.output_dir)

    ffmpeg_bin = state.config[:ffmpeg_bin] || "ffmpeg"
    hls_time = state.config[:hls_time] || 2
    hls_list_size = state.config[:hls_list_size] || 5

    segment_pattern = Path.join(state.output_dir, "seg_%05d.ts")
    index_path = Path.join(state.output_dir, "index.m3u8")

    args = [
      "-y",
      "-loglevel", "warning",
      "-rtsp_transport", "tcp",
      "-i", state.url,
      "-c", "copy",
      "-f", "hls",
      "-hls_time", to_string(hls_time),
      "-hls_list_size", to_string(hls_list_size),
      "-hls_flags", "delete_segments+append_list",
      "-hls_segment_filename", segment_pattern,
      index_path
    ]

    case System.find_executable(ffmpeg_bin) do
      nil ->
        {:error, :ffmpeg_not_found}

      executable ->
        port =
          Port.open(
            {:spawn_executable, executable},
            [:binary, :exit_status, :stderr_to_stdout, args: args]
          )

        # Try to get the OS PID for cleanup
        os_pid =
          case Port.info(port, :os_pid) do
            {:os_pid, pid} -> pid
            _ -> nil
          end

        {:ok, %{state | port: port, os_pid: os_pid, status: :starting}}
    end
  end

  defp kill_ffmpeg(%{port: nil}), do: :ok

  defp kill_ffmpeg(%{port: port, os_pid: os_pid}) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    # Ensure the OS process is dead
    if os_pid do
      System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)
    end

    :ok
  end

  defp cleanup_segments(output_dir) do
    if File.dir?(output_dir) do
      File.rm_rf!(output_dir)
    end
  end

  defp broadcast_status(uid, status) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "dashboard:events",
      {:hls_status, uid, status}
    )
  end

  defp schedule_ready_check(delay) do
    Process.send_after(self(), :check_ready, delay)
  end
end
