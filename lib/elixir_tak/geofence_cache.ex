defmodule ElixirTAK.GeofenceCache do
  @moduledoc """
  ETS-backed cache of geofence definitions (type `u-d-*` with `<__geofence>`).

  Geofences are shapes that carry trigger metadata (Entry/Exit/Both).
  They persist until explicitly deleted or they go stale. Stored
  separately from ShapeCache so the dashboard can render them with
  distinct visual treatment (amber outline, trigger labels).
  """

  use GenServer

  alias ElixirTAK.Protocol.CotEvent

  @table :geofence_cache

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Cache a geofence event, keyed by UID."
  def put(%CotEvent{uid: uid} = event, group \\ nil) do
    :ets.insert(@table, {uid, event, group})
    :ok
  end

  @doc "Remove a geofence by UID."
  def delete(uid) when is_binary(uid) do
    :ets.delete(@table, uid)
    :ok
  end

  def delete(nil), do: :ok

  @doc "Return all cached geofences (including stale ones)."
  def get_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_uid, event, _group} -> event end)
  end

  @doc "Return the count of cached geofences."
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
