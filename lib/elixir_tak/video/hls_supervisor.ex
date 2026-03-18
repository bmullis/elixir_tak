defmodule ElixirTAK.Video.HLSSupervisor do
  @moduledoc """
  DynamicSupervisor for HLS transcoding workers.

  Manages one `HLSWorker` per video stream that needs FFmpeg transcoding
  (RTSP/RTMP sources converted to HLS for browser playback).

  If FFmpeg is not installed, the supervisor starts but silently skips
  worker creation. RTSP/RTMP streams will show as "browser playback
  unavailable" in the dashboard, which is the same pre-13D behavior.
  """

  use DynamicSupervisor

  require Logger

  alias ElixirTAK.Video.HLSWorker

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Check for FFmpeg on startup, log once
    if ffmpeg_path() do
      Logger.info("HLS transcoding enabled (ffmpeg found)")
    else
      Logger.info(
        "HLS transcoding disabled (ffmpeg not found -- install ffmpeg for browser playback of RTSP/RTMP streams)"
      )
    end

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start an HLS transcoding worker for a video stream. No-op if FFmpeg is unavailable."
  def start_worker(attrs) when is_map(attrs) do
    if ffmpeg_path() do
      DynamicSupervisor.start_child(__MODULE__, {HLSWorker, attrs})
    else
      :ok
    end
  end

  @doc "Stop the HLS worker for a given stream UID."
  def stop_worker(uid) when is_binary(uid) do
    case Registry.lookup(ElixirTAK.Video.HLSRegistry, uid) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
  end

  @doc "Check if a worker is running for a given stream UID."
  def worker_running?(uid) when is_binary(uid) do
    Registry.lookup(ElixirTAK.Video.HLSRegistry, uid) != []
  end

  @doc "Check if FFmpeg is available for HLS transcoding."
  def available? do
    ffmpeg_path() != nil
  end

  defp ffmpeg_path do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    bin = config[:ffmpeg_bin] || "ffmpeg"
    System.find_executable(bin)
  end
end
