defmodule ElixirTAK.Federation.Transport.BEAM do
  @moduledoc """
  Federation transport using distributed Erlang and `:pg` process groups.

  Connects to remote BEAM nodes via `Node.connect/1` and uses the
  `ElixirTAK.PG` scope with the `:federation_managers` group to discover
  federation manager processes on peer nodes. Events are sent directly
  to remote managers via `send/2`, skipping local members.

  The `:pg` scope (`ElixirTAK.PG`) must be started separately in the
  supervision tree before this module.
  """

  @behaviour ElixirTAK.Federation.Transport

  use GenServer

  require Logger

  alias ElixirTAK.Federation.FedEvent

  @pg_scope ElixirTAK.PG
  @pg_group :federation_managers

  # -- Public API ------------------------------------------------------------

  @doc "Starts the BEAM federation transport GenServer."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connects to a remote BEAM node.

  Returns `{:ok, node_name}` on success or `{:error, reason}` if the
  connection fails.
  """
  @impl ElixirTAK.Federation.Transport
  def connect(node_name) when is_atom(node_name) do
    case Node.connect(node_name) do
      true -> {:ok, node_name}
      false -> {:error, :failed_to_connect}
      :ignored -> {:error, :not_alive}
    end
  end

  @doc "Disconnects from a remote BEAM node."
  @impl ElixirTAK.Federation.Transport
  def disconnect(node_name) when is_atom(node_name) do
    Node.disconnect(node_name)
    :ok
  end

  @doc """
  Sends a federation event to all `:pg` group members on remote nodes.

  Only targets processes where `node(pid) != node()` to avoid echoing
  events back to the local federation manager.
  """
  @impl ElixirTAK.Federation.Transport
  def send_event(%FedEvent{} = fed_event) do
    local = node()

    for pid <- :pg.get_members(@pg_scope, @pg_group), node(pid) != local do
      send(pid, {:fed_event, fed_event})
    end

    :ok
  end

  @doc """
  Returns the list of connected remote nodes that have federation managers
  registered in the `:pg` group.
  """
  @impl ElixirTAK.Federation.Transport
  def connected_peers do
    local = node()

    :pg.get_members(@pg_scope, @pg_group)
    |> Enum.map(&node/1)
    |> Enum.reject(&(&1 == local))
    |> Enum.uniq()
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl GenServer
  def init(opts) do
    manager = Keyword.fetch!(opts, :manager)

    :pg.join(@pg_scope, @pg_group, self())
    :net_kernel.monitor_nodes(true)

    Logger.info("BEAM federation transport started, joined pg group #{@pg_group}")

    {:ok, %{manager: manager}}
  end

  @impl GenServer
  def handle_info({:nodeup, node}, %{manager: manager} = state) do
    Logger.info("Federation: node connected - #{node}")
    send(manager, {:peer_connected, node})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:nodedown, node}, %{manager: manager} = state) do
    Logger.warning("Federation: node disconnected - #{node}")
    send(manager, {:peer_disconnected, node})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("BEAM transport received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :pg.leave(@pg_scope, @pg_group, self())
    :net_kernel.monitor_nodes(false)
    :ok
  end
end
