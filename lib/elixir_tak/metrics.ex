defmodule ElixirTAK.Metrics do
  @moduledoc """
  Tracks server metrics: event throughput, client counts, uptime.

  Uses :atomics for lock-free event counting and a 1-second tick to compute
  rolling rates. Broadcasts stats on the "dashboard:events" PubSub topic
  so dashboards can update without polling.
  """

  use GenServer

  alias ElixirTAK.{ClientRegistry, ChatCache}

  @pubsub ElixirTAK.PubSub
  @topic "dashboard:events"
  @tick_ms 1_000
  @window_size 60

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Record that an event of the given type was processed."
  def record_event(_type) do
    counter = :persistent_term.get(:metrics_event_counter)
    :atomics.add(counter, 1, 1)
  end

  @doc "Return current server stats."
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    counter = :atomics.new(1, signed: false)
    :persistent_term.put(:metrics_event_counter, counter)

    schedule_tick()

    {:ok,
     %{
       started_at: System.monotonic_time(:second),
       total_events: 0,
       last_count: 0,
       window: :queue.new(),
       window_size: 0
     }}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, build_stats(state), state}
  end

  @impl true
  def handle_info(:tick, state) do
    counter = :persistent_term.get(:metrics_event_counter)
    current_total = :atomics.get(counter, 1)
    events_this_second = current_total - state.last_count

    {window, window_size} = push_window(state.window, state.window_size, events_this_second)

    state = %{
      state
      | total_events: current_total,
        last_count: current_total,
        window: window,
        window_size: window_size
    }

    stats = build_stats(state)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:metrics_update, stats})

    schedule_tick()
    {:noreply, state}
  end

  # -- Private ---------------------------------------------------------------

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp push_window(queue, size, value) do
    queue = :queue.in(value, queue)

    if size >= @window_size do
      {{:value, _}, queue} = :queue.out(queue)
      {queue, size}
    else
      {queue, size + 1}
    end
  end

  defp events_per_second(window) do
    case :queue.peek_r(window) do
      {:value, val} -> val
      :empty -> 0
    end
  end

  defp events_per_minute(window) do
    :queue.to_list(window) |> Enum.sum()
  end

  defp build_stats(state) do
    uptime = System.monotonic_time(:second) - state.started_at
    memory_bytes = :erlang.memory(:total)
    memory_mb = Float.round(memory_bytes / 1_048_576, 1)
    counter = :persistent_term.get(:metrics_event_counter)

    %{
      total_events: :atomics.get(counter, 1),
      events_per_second: events_per_second(state.window),
      events_per_minute: events_per_minute(state.window),
      connected_clients: ClientRegistry.count(),
      sa_cached: :ets.info(:sa_cache, :size),
      chat_cached: ChatCache.count(),
      uptime_seconds: uptime,
      memory_mb: memory_mb
    }
    |> maybe_add_federation_stats()
  end

  defp maybe_add_federation_stats(stats) do
    if Application.get_env(:elixir_tak, ElixirTAK.Federation, [])[:enabled] &&
         GenServer.whereis(ElixirTAK.Federation.Manager) do
      fed_stats = ElixirTAK.Federation.Manager.get_stats()

      Map.merge(stats, %{
        federation_peers: fed_stats.peers_configured,
        federation_connected: fed_stats.peers_connected,
        federation_events_in: fed_stats.events_received,
        federation_events_out: fed_stats.events_sent
      })
    else
      stats
    end
  end
end
