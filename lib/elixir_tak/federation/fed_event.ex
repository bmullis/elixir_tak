defmodule ElixirTAK.Federation.FedEvent do
  @moduledoc """
  Wrapper around a `CotEvent` for federation transport.

  Tracks the originating server, hop count (to prevent infinite forwarding),
  and the sender's UID and group so the receiving server can broadcast the
  event through its local PubSub with proper attribution.
  """

  alias ElixirTAK.Protocol.CotEvent

  @max_hops 3

  @type t :: %__MODULE__{
          event: CotEvent.t(),
          source_server: String.t(),
          hop_count: non_neg_integer(),
          timestamp: DateTime.t(),
          sender_uid: String.t(),
          sender_group: String.t() | nil
        }

  defstruct [:event, :source_server, :hop_count, :timestamp, :sender_uid, :sender_group]

  @doc """
  Wraps a `CotEvent` for federation, setting hop_count to 1 and timestamping
  with the current UTC time.
  """
  @spec wrap(CotEvent.t(), String.t(), String.t(), String.t() | nil) :: t()
  def wrap(%CotEvent{} = event, server_uid, sender_uid, sender_group) do
    %__MODULE__{
      event: event,
      source_server: server_uid,
      hop_count: 1,
      timestamp: DateTime.utc_now(),
      sender_uid: sender_uid,
      sender_group: sender_group
    }
  end

  @doc """
  Returns `false` if the event has reached the maximum hop count and should
  not be forwarded further.
  """
  @spec should_forward?(t()) :: boolean()
  def should_forward?(%__MODULE__{hop_count: hop_count}) when hop_count >= @max_hops, do: false
  def should_forward?(%__MODULE__{}), do: true

  @doc """
  Returns a new `FedEvent` with the hop count incremented by one.
  """
  @spec increment_hop(t()) :: t()
  def increment_hop(%__MODULE__{hop_count: hop_count} = fed_event) do
    %{fed_event | hop_count: hop_count + 1}
  end
end
