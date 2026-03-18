defmodule ElixirTAKWeb.VideoController do
  @moduledoc """
  REST API for video stream management.

  Provides CRUD operations for video streams and CoT injection
  to push stream availability to connected TAK clients.
  """

  use Phoenix.Controller, formats: [:json]

  alias ElixirTAK.VideoRegistry

  @doc """
  GET /Marti/vcm - TAK Video Connection Manager endpoint.

  Returns XML with `<videoConnections>` containing `<feed>` elements,
  matching the format iTAK/ATAK expect when downloading video feeds
  from a TAK server.
  """
  def vcm(conn, _params) do
    streams = VideoRegistry.list()

    xml = [
      ~s(<?xml version="1.0" encoding="UTF-8"?>),
      "<videoConnections>",
      Enum.map(streams, &build_vcm_feed/1),
      "</videoConnections>"
    ]

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, IO.iodata_to_binary(xml))
  end

  @doc """
  GET /Marti/api/video - TAK-compatible video feed list (JSON).

  Returns JSON with `videoConnections` array matching the format
  iTAK expects when downloading video feeds from a TAK server.
  """
  def marti_video_list(conn, _params) do
    streams = VideoRegistry.list()

    video_connections =
      Enum.map(streams, fn stream ->
        {proto, addr, path, port} = VideoRegistry.tak_feed_params(stream)

        %{
          "protocol" => proto,
          "alias" => stream.alias || "Video Stream",
          "uid" => stream.uid,
          "address" => addr,
          "port" => port,
          "roverPort" => -1,
          "ignoreEmbeddedKLV" => false,
          "preferredMacAddress" => "",
          "preferredInterfaceAddress" => "",
          "path" => path,
          "buffer" => -1,
          "timeout" => 10000,
          "rtspReliable" => 1,
          "networkTimeout" => 12000
        }
      end)

    json(conn, %{"videoConnections" => video_connections})
  end

  @doc "GET /api/video - list all registered video streams"
  def index(conn, _params) do
    streams =
      VideoRegistry.list()
      |> Enum.map(&stream_to_json/1)

    json(conn, %{count: length(streams), streams: streams})
  end

  @doc "GET /api/video/:uid - get a single video stream"
  def show(conn, %{"uid" => uid}) do
    case VideoRegistry.get(uid) do
      {:ok, stream} ->
        json(conn, %{stream: stream_to_json(stream)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "stream not found"})
    end
  end

  @doc "POST /api/video - register a new video stream"
  def create(conn, params) do
    attrs = %{
      uid: params["uid"],
      url: params["url"],
      alias: params["alias"],
      lat: params["lat"],
      lon: params["lon"],
      hae: params["hae"]
    }

    case validate_create(attrs) do
      :ok ->
        {:ok, uid} = VideoRegistry.register(attrs)

        if params["broadcast"] != false do
          VideoRegistry.broadcast_cot(uid)
        end

        conn
        |> put_status(:created)
        |> json(%{uid: uid, status: "registered"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc "PUT /api/video/:uid - update a video stream"
  def update(conn, %{"uid" => uid} = params) do
    attrs = %{
      url: params["url"],
      alias: params["alias"],
      lat: params["lat"],
      lon: params["lon"],
      hae: params["hae"]
    }

    case VideoRegistry.update(uid, attrs) do
      {:ok, updated} ->
        if params["broadcast"] != false do
          VideoRegistry.broadcast_cot(uid)
        end

        json(conn, %{stream: stream_to_json(updated)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "stream not found"})
    end
  end

  @doc "DELETE /api/video/:uid - remove a video stream"
  def delete(conn, %{"uid" => uid}) do
    case VideoRegistry.delete(uid) do
      :ok ->
        json(conn, %{status: "deleted", uid: uid})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "stream not found"})
    end
  end

  @doc """
  GET /Marti/api/video/:uid/hls/:filename - serve HLS playlist or segments.

  Serves FFmpeg-generated HLS files from disk for browser playback.
  """
  def hls(conn, %{"uid" => uid, "filename" => filename}) do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    hls_dir = config[:hls_dir] || "data/hls"

    # Sanitize filename to prevent directory traversal
    safe_filename = Path.basename(filename)
    file_path = Path.join([hls_dir, uid, safe_filename])

    cond do
      not File.exists?(file_path) ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not found"})

      String.ends_with?(safe_filename, ".m3u8") ->
        conn
        |> put_resp_content_type("application/vnd.apple.mpegurl")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_file(200, file_path)

      String.ends_with?(safe_filename, ".ts") ->
        conn
        |> put_resp_content_type("video/MP2T")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_file(200, file_path)

      true ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "unsupported file type"})
    end
  end

  @doc """
  POST /Marti/api/video/:uid/snapshot - capture a single frame from a video stream.

  Uses FFmpeg to grab one frame and save it as a JPEG.
  """
  def snapshot(conn, %{"uid" => uid}) do
    case VideoRegistry.get(uid) do
      {:ok, stream} ->
        case capture_snapshot(stream) do
          {:ok, snapshot_url} ->
            json(conn, %{status: "captured", uid: uid, snapshot_url: snapshot_url})

          {:error, :ffmpeg_not_found} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: "ffmpeg not installed -- install ffmpeg for snapshot support"})

          {:error, reason} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: to_string(reason)})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "stream not found"})
    end
  end

  @doc """
  GET /Marti/api/video/:uid/snapshot/latest - serve the most recent snapshot.
  """
  def latest_snapshot(conn, %{"uid" => uid}) do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    snapshot_dir = config[:snapshot_dir] || "data/snapshots"
    stream_dir = Path.join(snapshot_dir, uid)

    case latest_snapshot_file(stream_dir) do
      {:ok, file_path} ->
        conn
        |> put_resp_content_type("image/jpeg")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_file(200, file_path)

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "no snapshot available"})
    end
  end

  # -- Private ---------------------------------------------------------------

  defp capture_snapshot(stream) do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    ffmpeg_bin = config[:ffmpeg_bin] || "ffmpeg"
    snapshot_dir = config[:snapshot_dir] || "data/snapshots"
    stream_dir = Path.join(snapshot_dir, stream.uid)

    File.mkdir_p!(stream_dir)

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    filename = "#{timestamp}.jpg"
    output_path = Path.join(stream_dir, filename)

    case System.find_executable(ffmpeg_bin) do
      nil ->
        {:error, :ffmpeg_not_found}

      executable ->
        args = [
          "-y",
          "-rtsp_transport",
          "tcp",
          "-i",
          stream.url,
          "-frames:v",
          "1",
          "-f",
          "image2",
          output_path
        ]

        case System.cmd(executable, args, stderr_to_stdout: true, timeout: 15_000) do
          {_output, 0} ->
            url = "/Marti/api/video/#{stream.uid}/snapshot/latest"
            {:ok, url}

          {output, code} ->
            {:error, "ffmpeg exited with code #{code}: #{String.slice(output, 0, 200)}"}
        end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp latest_snapshot_file(dir) do
    if File.dir?(dir) do
      case dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".jpg")) |> Enum.sort(:desc) do
        [latest | _] -> {:ok, Path.join(dir, latest)}
        [] -> :error
      end
    else
      :error
    end
  end

  defp validate_create(attrs) do
    cond do
      is_nil(attrs.url) or attrs.url == "" ->
        {:error, "url is required"}

      true ->
        :ok
    end
  end

  defp build_vcm_feed(stream) do
    {proto, addr, path, port} = VideoRegistry.tak_feed_params(stream)

    IO.iodata_to_binary([
      "<feed>",
      "<protocol>",
      xml_escape(proto),
      "</protocol>",
      "<alias>",
      xml_escape(stream.alias || "Video Stream"),
      "</alias>",
      "<uid>",
      xml_escape(stream.uid),
      "</uid>",
      "<address>",
      xml_escape(addr),
      "</address>",
      "<port>",
      to_string(port),
      "</port>",
      "<roverPort>-1</roverPort>",
      "<ignoreEmbeddedKLV>false</ignoreEmbeddedKLV>",
      "<preferredMacAddress></preferredMacAddress>",
      "<preferredInterfaceAddress></preferredInterfaceAddress>",
      "<path>",
      xml_escape(path),
      "</path>",
      "<buffer>-1</buffer>",
      "<timeout>10000</timeout>",
      "<rtspReliable>1</rtspReliable>",
      "</feed>"
    ])
  end

  defp xml_escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp stream_to_json(stream) do
    %{
      uid: stream.uid,
      url: stream.url,
      alias: stream.alias,
      protocol: stream.protocol,
      lat: stream.lat,
      lon: stream.lon,
      hae: stream.hae,
      created_at: stream.created_at && DateTime.to_iso8601(stream.created_at),
      updated_at: stream.updated_at && DateTime.to_iso8601(stream.updated_at)
    }
  end
end
