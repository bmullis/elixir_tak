defmodule ElixirTAK.History.Writer do
  @moduledoc """
  Async GenServer that batches CoT events and writes them to SQLite.

  Events are cast to this process and accumulated in a buffer. The buffer
  is flushed to the database either when it reaches `@max_batch` size or
  when the `@flush_interval` timer fires, whichever comes first. This
  ensures the CoT pipeline is never blocked by disk I/O.
  """

  use GenServer

  require Logger

  alias ElixirTAK.History.EventRecord
  alias ElixirTAK.Repo

  @flush_interval 1_000
  @max_batch 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Record a CoT event asynchronously. Never blocks the caller."
  def record(cot_event, raw_xml, group, opts \\ []) do
    GenServer.cast(__MODULE__, {:record, cot_event, raw_xml, group, opts})
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    schedule_flush()
    {:ok, %{buffer: [], count: 0}}
  end

  @impl true
  def handle_cast({:record, cot_event, raw_xml, group, opts}, state) do
    row = EventRecord.from_cot_event(cot_event, raw_xml, group, opts)
    state = %{state | buffer: [row | state.buffer], count: state.count + 1}

    if state.count >= @max_batch do
      {:noreply, flush(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    state = flush(state)
    schedule_flush()
    {:noreply, state}
  end

  # -- Private ---------------------------------------------------------------

  defp flush(%{buffer: [], count: 0} = state), do: state

  defp flush(%{buffer: buffer} = _state) do
    try do
      Repo.insert_all(EventRecord, Enum.reverse(buffer))
    rescue
      e ->
        Logger.warning("History.Writer flush failed: #{Exception.message(e)}")
    end

    %{buffer: [], count: 0}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
