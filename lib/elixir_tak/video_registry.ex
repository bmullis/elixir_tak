defmodule ElixirTAK.VideoRegistry do
  @moduledoc """
  ETS-backed registry of video stream metadata.

  Stores registered video streams (RTSP/RTMP/HLS URLs with position and alias)
  and can broadcast corresponding CoT events (`b-i-v`) so ATAK/iTAK clients
  see video feeds natively.
  """

  use GenServer

  require Logger

  alias ElixirTAK.Protocol.CotEvent
  alias ElixirTAK.Video.HLSSupervisor
  alias ElixirTAK.VideoCache

  @table :video_registry
  @pubsub ElixirTAK.PubSub
  @cot_topic "cot:broadcast"

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Register a new video stream. Returns `{:ok, uid}` on success."
  def register(attrs) when is_map(attrs) do
    uid = Map.get(attrs, :uid) || Map.get(attrs, "uid") || generate_uid()

    stream = %{
      uid: uid,
      url: attrs[:url] || attrs["url"],
      alias: attrs[:alias] || attrs["alias"] || "Video Stream",
      protocol: detect_protocol(attrs[:url] || attrs["url"]),
      lat: parse_float(attrs[:lat] || attrs["lat"]),
      lon: parse_float(attrs[:lon] || attrs["lon"]),
      hae: parse_float(attrs[:hae] || attrs["hae"]),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    :ets.insert(@table, {uid, stream})
    VideoCache.put(build_cot_event(stream))
    maybe_start_hls(stream)
    Logger.info("Video stream registered: #{stream.alias} (#{uid})")

    Phoenix.PubSub.broadcast(
      @pubsub,
      "dashboard:events",
      {:video_stream_added, stream}
    )

    {:ok, uid}
  end

  @doc "Update an existing video stream's metadata."
  def update(uid, attrs) when is_binary(uid) and is_map(attrs) do
    case :ets.lookup(@table, uid) do
      [{^uid, existing}] ->
        updated =
          existing
          |> maybe_update(:url, attrs)
          |> maybe_update(:alias, attrs)
          |> maybe_update(:lat, attrs, &parse_float/1)
          |> maybe_update(:lon, attrs, &parse_float/1)
          |> maybe_update(:hae, attrs, &parse_float/1)
          |> Map.put(:updated_at, DateTime.utc_now())
          |> then(fn s -> %{s | protocol: detect_protocol(s.url)} end)

        :ets.insert(@table, {uid, updated})
        VideoCache.put(build_cot_event(updated))

        # Restart HLS worker if URL changed
        if existing.url != updated.url do
          HLSSupervisor.stop_worker(uid)
          maybe_start_hls(updated)
        end

        Phoenix.PubSub.broadcast(
          @pubsub,
          "dashboard:events",
          {:video_stream_updated, updated}
        )

        {:ok, updated}

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Remove a video stream. Broadcasts a delete CoT event to all connected clients."
  def delete(uid) when is_binary(uid) do
    case :ets.lookup(@table, uid) do
      [{^uid, _}] ->
        HLSSupervisor.stop_worker(uid)
        :ets.delete(@table, uid)
        VideoCache.delete(uid)
        broadcast_delete_cot(uid)

        Phoenix.PubSub.broadcast(
          @pubsub,
          "dashboard:events",
          {:video_stream_removed, uid}
        )

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Get a single stream by UID."
  def get(uid) when is_binary(uid) do
    case :ets.lookup(@table, uid) do
      [{^uid, stream}] -> {:ok, stream}
      [] -> {:error, :not_found}
    end
  end

  @doc "List all registered video streams."
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_uid, stream} -> stream end)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  end

  @doc """
  Broadcast a CoT event for a video stream so ATAK/iTAK clients can see it.

  Generates a `b-i-v` (bits-image-video) typed event with a `__video` detail
  element containing the stream URL and connection info.
  """
  def broadcast_cot(uid) when is_binary(uid) do
    case get(uid) do
      {:ok, stream} ->
        event = build_cot_event(stream)

        Phoenix.PubSub.broadcast(
          @pubsub,
          @cot_topic,
          {:cot_broadcast, uid, event, nil}
        )

      error ->
        error
    end
  end

  @doc "Broadcast CoT events for all registered streams."
  def broadcast_all do
    for stream <- list() do
      broadcast_cot(stream.uid)
    end

    :ok
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, []}
  end

  # -- Private ---------------------------------------------------------------

  defp generate_uid do
    "video-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp detect_protocol(nil), do: "unknown"

  defp detect_protocol(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "rtsp://") -> "rtsp"
      String.starts_with?(url, "rtmp://") -> "rtmp"
      String.contains?(url, ".m3u8") -> "hls"
      String.starts_with?(url, "http") -> "http"
      true -> "unknown"
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val / 1

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp maybe_update(map, key, attrs, transform \\ nil) do
    str_key = to_string(key)

    case Map.get(attrs, key) || Map.get(attrs, str_key) do
      nil -> map
      val -> Map.put(map, key, if(transform, do: transform.(val), else: val))
    end
  end

  defp broadcast_delete_cot(uid) do
    now = DateTime.utc_now()

    event = %CotEvent{
      uid: "delete-" <> uid,
      type: "t-x-d-d",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: DateTime.add(now, 60, :second),
      point: %{lat: 0.0, lon: 0.0, hae: 9_999_999.0, ce: 9_999_999.0, le: 9_999_999.0},
      detail: nil,
      raw_detail:
        "<detail><link uid=\"#{escape(uid)}\" relation=\"p-p\" type=\"b-i-v\"/></detail>"
    }

    Phoenix.PubSub.broadcast(
      @pubsub,
      @cot_topic,
      {:cot_broadcast, uid, event, nil}
    )
  end

  defp build_cot_event(stream) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    raw_detail = build_video_detail(stream)

    %CotEvent{
      uid: stream.uid,
      type: "b-i-v",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: stale,
      point: %{
        lat: stream.lat || 0.0,
        lon: stream.lon || 0.0,
        hae: stream.hae || 9_999_999.0,
        ce: 9_999_999.0,
        le: 9_999_999.0
      },
      detail: nil,
      raw_detail: IO.iodata_to_binary(raw_detail)
    }
  end

  defp build_video_detail(stream) do
    {proto, _addr, _path, _port} = tak_feed_params(stream)

    [
      "<detail>",
      "<__video",
      " url=\"",
      escape(stream.url || ""),
      "\"",
      " protocol=\"",
      escape(proto),
      "\"",
      "/>",
      build_connection_entry(stream),
      "<contact callsign=\"",
      escape(stream.alias),
      "\"/>",
      "</detail>"
    ]
  end

  @doc """
  Build a connectionEntry XML fragment for a stream (used by VCM endpoint).

  When `hostname` is provided, it overrides the address in the URL so the client
  connects back to the server it fetched from. When `itak?` is true, the address
  is a full `protocol://host:port/path` URL (iTAK expects this format).
  """
  def build_connection_entry(stream, hostname \\ nil, _itak? \\ false) do
    {proto, addr, path, port} = tak_feed_params(stream, hostname)
    alias_str = stream.alias || "Video Stream"

    [
      "<connectionEntry",
      " networkTimeout=\"12000\"",
      " uid=\"",
      escape(stream.uid),
      "\"",
      " path=\"",
      escape(path),
      "\"",
      " protocol=\"",
      escape(proto),
      "\"",
      " alias=\"",
      escape(alias_str),
      "\"",
      " address=\"",
      escape(addr),
      "\"",
      " port=\"",
      escape(to_string(port)),
      "\"",
      " roverPort=\"-1\"",
      " rtspReliable=\"1\"",
      " ignoreEmbeddedKLV=\"false\"",
      " buffer=\"-1\"",
      " timeout=\"10000\"",
      "/>"
    ]
  end

  @doc """
  Compute TAK-compatible feed parameters for a stream.

  Returns `{protocol, address, path, port}` where:
  - For RTSP: protocol="rtsp", address=hostname, path=URL path, port=RTSP port
  - For HTTP/HLS: protocol="raw", address=full URL, path="", port=HTTP port

  TAK clients (iTAK especially) use protocol="raw" to mean "use the address
  field as a complete URL". Setting protocol="http" causes iTAK to fall back
  to its own "raw" mode incorrectly. This matches FreeTAKServer behavior.
  """
  def tak_feed_params(stream, _hostname \\ nil) do
    protocol = stream.protocol || "rtsp"
    url = stream.url || ""

    # Always use the original URL's host/port/path. The hostname override was
    # intended for when the TAK server proxies streams (RTSP relay), but for
    # direct streams the client must connect to the actual stream source.
    host = extract_host(url)
    port = extract_port(url, protocol)

    case protocol do
      "rtsp" ->
        path = case URI.parse(url) do
          %URI{path: p} when is_binary(p) and p != "" -> p
          _ -> ""
        end
        {"rtsp", host, path, port}

      "rtmp" ->
        path = case URI.parse(url) do
          %URI{path: p} when is_binary(p) and p != "" -> p
          _ -> ""
        end
        {"rtmp", host, path, port}

      _ ->
        # HLS, HTTP, and anything else: use "raw" protocol with the full URL
        # as the address. TAK clients treat "raw" as "play this URL directly".
        {"raw", url, "", port}
    end
  end

  @doc "Extract hostname from a URL string."
  def extract_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> ""
    end
  end

  def extract_host(_), do: ""

  @doc "Extract port from a URL string, falling back to protocol default."
  def extract_port(url, protocol) when is_binary(url) do
    case URI.parse(url) do
      %URI{port: port} when is_integer(port) -> port
      _ -> default_port(protocol)
    end
  end

  def extract_port(_, protocol), do: default_port(protocol)

  defp default_port("rtsp"), do: 554
  defp default_port("rtmp"), do: 1935
  defp default_port("hls"), do: 443
  defp default_port("http"), do: 80
  defp default_port("srt"), do: 9710
  defp default_port(_), do: 0

  defp maybe_start_hls(stream) do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    hls_enabled = config[:enabled] != false

    if hls_enabled and stream.protocol in ["rtsp", "rtmp"] do
      HLSSupervisor.start_worker(%{
        uid: stream.uid,
        url: stream.url,
        protocol: stream.protocol
      })
    end
  end

  @doc "Return the HLS playlist URL for a stream (relative path)."
  def hls_url(uid) when is_binary(uid) do
    "/Marti/api/video/#{uid}/hls/index.m3u8"
  end

  @doc "Check if HLS segments are available for a stream."
  def hls_available?(uid) when is_binary(uid) do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])
    hls_dir = config[:hls_dir] || "data/hls"
    File.exists?(Path.join([hls_dir, uid, "index.m3u8"]))
  end

  defp escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
