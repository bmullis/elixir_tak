defmodule ElixirTAKWeb.Plugs.RateLimiter do
  @moduledoc """
  Simple ETS-based rate limiter plug.

  Tracks request counts per token (or IP for unauthenticated) in a
  sliding window. Defaults to 100 requests per 60 seconds.
  """

  import Plug.Conn

  @behaviour Plug

  @table :rate_limiter
  @default_limit 100
  @default_window_ms 60_000

  @impl true
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    }
  end

  @impl true
  def call(conn, %{limit: limit, window_ms: window_ms}) do
    ensure_table()
    key = rate_limit_key(conn)
    now = System.monotonic_time(:millisecond)
    window_start = now - window_ms

    # Clean old entries and count current window
    entries =
      case :ets.lookup(@table, key) do
        [{^key, timestamps}] ->
          Enum.filter(timestamps, &(&1 > window_start))

        [] ->
          []
      end

    if length(entries) >= limit do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("retry-after", to_string(div(window_ms, 1000)))
      |> send_resp(
        429,
        Jason.encode!(%{error: "Rate limit exceeded", retry_after_seconds: div(window_ms, 1000)})
      )
      |> halt()
    else
      :ets.insert(@table, {key, [now | entries]})
      conn
    end
  end

  defp rate_limit_key(conn) do
    case conn.assigns[:api_token] do
      %{id: id} -> "token:#{id}"
      _ -> "ip:#{:inet.ntoa(conn.remote_ip)}"
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
