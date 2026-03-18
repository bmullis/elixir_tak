defmodule ElixirTAK.MarkerCache do
  @moduledoc """
  ETS-backed cache of user-placed markers (type `b-m-p-*`).

  Markers are collaborative annotations placed by TAK clients on the map.
  Unlike SA events (which track live positions), markers persist until they
  go stale. Stale markers are kept but flagged so the UI can dim them.
  """

  use GenServer

  alias ElixirTAK.Protocol.CotEvent

  @table :marker_cache

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Cache a marker event, keyed by UID."
  def put(%CotEvent{uid: uid} = event, group \\ nil) do
    :ets.insert(@table, {uid, event, group})
    :ok
  end

  @doc "Remove a marker by UID."
  def delete(uid) when is_binary(uid) do
    :ets.delete(@table, uid)
    :ok
  end

  def delete(nil), do: :ok

  @doc "Return all cached markers (including stale ones)."
  def get_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_uid, event, _group} -> event end)
  end

  @doc "Return the count of cached markers."
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
