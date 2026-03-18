defmodule ElixirTAK.Federation.Transport do
  @moduledoc """
  Behaviour for swappable federation transports.

  Implementations handle the mechanics of connecting to peer TAK servers
  and exchanging `FedEvent` messages. The federation manager calls these
  callbacks without knowing whether the underlying transport is distributed
  Erlang, NATS, TCP, or something else entirely.
  """

  alias ElixirTAK.Federation.FedEvent

  @doc "Establish a connection to a peer server using the given config."
  @callback connect(config :: term()) :: {:ok, pid()} | {:error, term()}

  @doc "Disconnect from a peer identified by `peer_id`."
  @callback disconnect(peer_id :: term()) :: :ok

  @doc "Send a federated event to connected peers."
  @callback send_event(FedEvent.t()) :: :ok | {:error, term()}

  @doc "List currently connected peer identifiers."
  @callback connected_peers() :: [term()]
end
