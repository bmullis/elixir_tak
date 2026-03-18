defmodule ElixirTAK.SACache do
  @moduledoc """
  ETS-backed cache of the latest SA (Situational Awareness) event per UID.

  New clients receive all cached (non-stale) events on connect so they
  immediately see the current picture without waiting for everyone to
  transmit again.
  """

  use GenServer

  require Logger

  alias ElixirTAK.History.{EventRecord, Queries}
  alias ElixirTAK.Protocol.CotEvent

  @table :sa_cache

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Cache the latest event for a UID, optionally with a group."
  def put(%CotEvent{uid: uid} = event, group \\ nil) do
    :ets.insert(@table, {uid, event, group})
    :ok
  end

  @doc "Remove a UID from the cache (e.g. on disconnect)."
  def delete(uid) when is_binary(uid) do
    :ets.delete(@table, uid)
    :ok
  end

  def delete(nil), do: :ok

  @doc "Return all cached events that are not stale."
  def get_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_uid, event, _group} -> event end)
    |> Enum.reject(&CotEvent.stale?/1)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    restore_from_history()
    {:ok, []}
  end

  defp restore_from_history do
    for record <- Queries.latest_per_uid(limit: 1000) do
      event = EventRecord.to_cot_event(record)

      # Only restore actual SA events (a-*) — not emergency (b-a-o-*),
      # chat, markers, etc. that may share the same UID space.
      if String.starts_with?(event.type, "a-") and not CotEvent.stale?(event) do
        put(event, record.group_name)
      end
    end

    count = :ets.info(@table, :size)

    if count > 0 do
      Logger.info("SACache restored #{count} positions from history")
    end
  rescue
    _ -> :ok
  end
end
