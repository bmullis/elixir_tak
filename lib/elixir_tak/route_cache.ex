defmodule ElixirTAK.RouteCache do
  @moduledoc """
  ETS-backed cache of shared routes (type `b-m-r`).

  Routes are ordered sequences of waypoints shared by TAK clients.
  They persist until explicitly deleted or they go stale. Stale routes
  are kept but flagged so the UI can dim them.
  """

  use GenServer

  alias ElixirTAK.Protocol.CotEvent

  @table :route_cache

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Cache a route event, keyed by UID."
  def put(%CotEvent{uid: uid} = event, group \\ nil) do
    :ets.insert(@table, {uid, event, group})
    :ok
  end

  @doc "Remove a route by UID."
  def delete(uid) when is_binary(uid) do
    :ets.delete(@table, uid)
    :ok
  end

  def delete(nil), do: :ok

  @doc "Return all cached routes (including stale ones)."
  def get_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_uid, event, _group} -> event end)
  end

  @doc "Return the count of cached routes."
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
