defmodule ElixirTAK.ChatCache do
  @moduledoc """
  ETS-backed bounded cache of recent chat messages.

  Stores the most recent @max_messages chat events in an ordered_set
  keyed by a monotonic counter. New clients receive the full chat
  history on connect.
  """

  use GenServer

  alias ElixirTAK.Protocol.{ChatParser, CotEvent}

  @table :chat_cache
  @counter :chat_cache_counter
  @max_messages 200

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store a chat event. Automatically prunes oldest messages when over limit."
  def put(%CotEvent{} = event) do
    seq = :atomics.add_get(:persistent_term.get(@counter), 1, 1)

    chatroom =
      case ChatParser.extract_chatroom(event.raw_detail || "") do
        {:ok, room} -> room
        :error -> "unknown"
      end

    :ets.insert(@table, {seq, event, chatroom})
    maybe_prune()
    :ok
  end

  @doc "Return all cached chat messages, newest first."
  def get_all do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {seq, _event, _room} -> seq end, :desc)
    |> Enum.map(fn {_seq, event, _room} -> event end)
  end

  @doc "Return chat messages for a specific chatroom, newest first."
  def get_by_room(room_name) do
    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {_seq, _event, room} -> room == room_name end)
    |> Enum.sort_by(fn {seq, _event, _room} -> seq end, :desc)
    |> Enum.map(fn {_seq, event, _room} -> event end)
  end

  @doc "Return message count."
  def count do
    :ets.info(@table, :size)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :ordered_set, read_concurrency: true])
    counter = :atomics.new(1, signed: false)
    :persistent_term.put(@counter, counter)
    {:ok, []}
  end

  # -- Private ---------------------------------------------------------------

  defp maybe_prune do
    size = :ets.info(@table, :size)

    if size > @max_messages do
      # ordered_set: first_key is the lowest (oldest)
      to_delete = size - @max_messages

      keys =
        Stream.unfold(:ets.first(@table), fn
          :"$end_of_table" -> nil
          key -> {key, :ets.next(@table, key)}
        end)
        |> Enum.take(to_delete)

      Enum.each(keys, &:ets.delete(@table, &1))
    end
  end
end
