defmodule ElixirTAK.VideoCache do
  @moduledoc """
  ETS-backed cache of video feed CoT events (type `b-i-v`).

  Stores the latest CoT event per video stream UID so that late-joining
  TAK clients receive all registered video feeds on connect, just like
  SA events are replayed from SACache.
  """

  use GenServer

  alias ElixirTAK.Protocol.CotEvent

  @table :video_cache

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Cache a video feed CoT event, keyed by UID."
  def put(%CotEvent{uid: uid} = event, group \\ nil) do
    :ets.insert(@table, {uid, event, group})
    :ok
  end

  @doc "Remove a video feed by UID."
  def delete(uid) when is_binary(uid) do
    :ets.delete(@table, uid)
    :ok
  end

  def delete(nil), do: :ok

  @doc "Return all cached video feed events (excluding stale)."
  def get_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_uid, event, _group} -> event end)
    |> Enum.reject(&CotEvent.stale?/1)
  end

  @doc "Return the count of cached video feeds."
  def count do
    :ets.info(@table, :size)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, []}
  end
end
