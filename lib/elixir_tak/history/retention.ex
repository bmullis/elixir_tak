defmodule ElixirTAK.History.Retention do
  @moduledoc """
  Periodic cleanup of old event history records.

  Configurable via:

      config :elixir_tak, ElixirTAK.History.Retention,
        max_age_hours: 168,
        cleanup_interval_minutes: 60
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias ElixirTAK.History.EventRecord
  alias ElixirTAK.Repo

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, []}
  end

  @impl true
  def handle_info(:cleanup, state) do
    run_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  @doc "Run retention cleanup immediately. Returns the number of deleted records."
  def run_cleanup do
    max_age_hours = config(:max_age_hours, 168)
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_hours * 3600, :second)

    {deleted, _} =
      from(e in EventRecord, where: e.event_time < ^cutoff)
      |> Repo.delete_all()

    if deleted > 0 do
      Logger.info("History retention: deleted #{deleted} events older than #{max_age_hours}h")
    end

    deleted
  end

  defp schedule_cleanup do
    interval_min = config(:cleanup_interval_minutes, 60)
    Process.send_after(self(), :cleanup, interval_min * 60_000)
  end

  defp config(key, default) do
    Application.get_env(:elixir_tak, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
