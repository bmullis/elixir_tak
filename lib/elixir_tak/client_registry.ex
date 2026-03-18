defmodule ElixirTAK.ClientRegistry do
  @moduledoc """
  ETS-backed registry of connected TAK clients.

  Tracks connection metadata (callsign, group, peer, cert CN, connect time).
  Broadcasts connect/disconnect events on the "dashboard:events" PubSub topic
  so dashboards can update in real time.
  """

  use GenServer

  @table :client_registry
  @pubsub ElixirTAK.PubSub
  @topic "dashboard:events"

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Register a connected client with metadata."
  def register(uid, attrs) when is_binary(uid) and is_map(attrs) do
    attrs = Map.put_new(attrs, :connected_at, DateTime.utc_now())
    :ets.insert(@table, {uid, attrs})
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:client_connected, uid, attrs})
    :ok
  end

  @doc "Update fields for an existing client."
  def update(uid, fields) when is_binary(uid) and is_map(fields) do
    case :ets.lookup(@table, uid) do
      [{^uid, existing}] ->
        :ets.insert(@table, {uid, Map.merge(existing, fields)})
        :ok

      [] ->
        :ok
    end
  end

  @doc "Remove a client from the registry (on disconnect)."
  def unregister(uid) when is_binary(uid) do
    :ets.delete(@table, uid)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:client_disconnected, uid})
    :ok
  end

  def unregister(nil), do: :ok

  @doc "Return all registered clients as a list of maps with :uid included."
  def get_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {uid, attrs} -> Map.put(attrs, :uid, uid) end)
  end

  @doc "Look up the handler PID for a connected client by UID."
  def lookup_pid(uid) when is_binary(uid) do
    case :ets.lookup(@table, uid) do
      [{^uid, %{handler_pid: pid}}] when is_pid(pid) -> {:ok, pid}
      _ -> :error
    end
  end

  @doc "Return the number of registered clients."
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
