defmodule ElixirTAK.Federation.Policy do
  @moduledoc """
  Determines which CoT events should cross federation boundaries.

  Pure functions with no side effects. Federated types include situational
  awareness (a-*), chat (b-t-f), emergency/alerts (b-a-*), markers (b-m-*),
  and shapes/drawings (u-d-*).
  """

  alias ElixirTAK.Protocol.CotEvent

  @doc """
  Returns `true` if the given event type should be federated to peer servers.
  """
  @spec federate?(CotEvent.t()) :: boolean()
  def federate?(%CotEvent{type: "a-" <> _}), do: true
  def federate?(%CotEvent{type: "b-t-f" <> _}), do: true
  def federate?(%CotEvent{type: "b-a-" <> _}), do: true
  def federate?(%CotEvent{type: "b-m-" <> _}), do: true
  def federate?(%CotEvent{type: "u-d-" <> _}), do: true
  def federate?(%CotEvent{}), do: false

  @doc """
  Returns `true` if an incoming federated event from `source_server` should
  be accepted. Currently accepts all events; this hook exists for future
  filtering by server identity, trust level, or event content.
  """
  @spec accept?(CotEvent.t(), source_server :: term()) :: boolean()
  def accept?(%CotEvent{}, _source_server), do: true
end
