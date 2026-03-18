defmodule ElixirTAK.Federation.IntegrationTest do
  @moduledoc """
  Two-node federation integration test using LocalCluster.

  Requires distributed Erlang. Run with:

      elixir --sname test -S mix test test/elixir_tak/federation/integration_test.exs --include federation

  Skipped by default since it requires the node to be started in distributed mode.
  """

  use ExUnit.Case, async: false

  @moduletag :federation

  setup do
    # LocalCluster requires the current node to be distributed
    unless Node.alive?() do
      flunk(
        "This test requires distributed Erlang. Run with: elixir --sname test -S mix test --include federation"
      )
    end

    :ok
  end

  test "SA event on node A appears on node B via federation" do
    # Start two nodes with our application
    [node_a, node_b] =
      LocalCluster.start_nodes("fed-test", 2,
        applications: [:elixir_tak],
        environment: [
          elixir_tak: [
            {ElixirTAK.Federation,
             [
               enabled: true,
               transport: :beam,
               server_name: "test-node",
               peers: []
             ]},
            {:tcp_port, 0},
            {:tls_enabled, false},
            {:simulator, false}
          ]
        ]
      )

    # Give nodes time to start their supervision trees
    Process.sleep(2000)

    # Connect the nodes' federation managers to each other
    :ok = :rpc.call(node_a, ElixirTAK.Federation.Manager, :add_peer, [node_b])
    Process.sleep(1000)

    # Verify federation is active on both nodes
    stats_a = :rpc.call(node_a, ElixirTAK.Federation.Manager, :get_stats, [])
    assert is_binary(stats_a.server_uid)

    stats_b = :rpc.call(node_b, ElixirTAK.Federation.Manager, :get_stats, [])
    assert is_binary(stats_b.server_uid)
    assert stats_a.server_uid != stats_b.server_uid

    # Create an SA event and broadcast it on node A
    event = %ElixirTAK.Protocol.CotEvent{
      uid: "fed-test-client-1",
      type: "a-f-G-U-C",
      how: "m-g",
      time: DateTime.utc_now(),
      start: DateTime.utc_now(),
      stale: DateTime.add(DateTime.utc_now(), 600, :second),
      point: %{lat: 33.5, lon: -111.9, hae: nil, ce: nil, le: nil},
      detail: %{callsign: "FedTest1"},
      raw_detail: "<detail><contact callsign=\"FedTest1\"/></detail>"
    }

    :rpc.call(node_a, Phoenix.PubSub, :broadcast, [
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, "fed-test-client-1", event, "Cyan"}
    ])

    # Wait for federation relay
    Process.sleep(1000)

    # Verify the event appeared in node B's SACache
    cached_b = :rpc.call(node_b, ElixirTAK.SACache, :get_all, [])
    cached_uids = Enum.map(cached_b, & &1.uid)

    assert "fed-test-client-1" in cached_uids,
           "Expected federated SA event to appear in node B's SACache. Got UIDs: #{inspect(cached_uids)}"

    # Verify outbound stats on node A
    stats_a = :rpc.call(node_a, ElixirTAK.Federation.Manager, :get_stats, [])
    assert stats_a.events_sent > 0

    # Verify inbound stats on node B
    stats_b = :rpc.call(node_b, ElixirTAK.Federation.Manager, :get_stats, [])
    assert stats_b.events_received > 0

    # Cleanup
    LocalCluster.stop_nodes([node_a, node_b])
  end

  test "non-federable event type does not cross federation boundary" do
    [node_a, node_b] =
      LocalCluster.start_nodes("fed-filter", 2,
        applications: [:elixir_tak],
        environment: [
          elixir_tak: [
            {ElixirTAK.Federation,
             [
               enabled: true,
               transport: :beam,
               server_name: "filter-node",
               peers: []
             ]},
            {:tcp_port, 0},
            {:tls_enabled, false},
            {:simulator, false}
          ]
        ]
      )

    Process.sleep(2000)

    :ok = :rpc.call(node_a, ElixirTAK.Federation.Manager, :add_peer, [node_b])
    Process.sleep(1000)

    # Broadcast a non-federable event (protocol negotiation)
    event = %ElixirTAK.Protocol.CotEvent{
      uid: "proto-neg-1",
      type: "t-x-takp-q",
      how: "m-g",
      time: DateTime.utc_now(),
      start: DateTime.utc_now(),
      stale: DateTime.add(DateTime.utc_now(), 600, :second),
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{},
      raw_detail: nil
    }

    :rpc.call(node_a, Phoenix.PubSub, :broadcast, [
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, "proto-neg-1", event, nil}
    ])

    Process.sleep(1000)

    # Verify it did NOT appear on node B
    stats_b = :rpc.call(node_b, ElixirTAK.Federation.Manager, :get_stats, [])
    assert stats_b.events_received == 0

    LocalCluster.stop_nodes([node_a, node_b])
  end

  test "event does not bounce back to originator (loop prevention)" do
    [node_a, node_b] =
      LocalCluster.start_nodes("fed-loop", 2,
        applications: [:elixir_tak],
        environment: [
          elixir_tak: [
            {ElixirTAK.Federation,
             [
               enabled: true,
               transport: :beam,
               server_name: "loop-node",
               peers: []
             ]},
            {:tcp_port, 0},
            {:tls_enabled, false},
            {:simulator, false}
          ]
        ]
      )

    Process.sleep(2000)

    # Connect both ways
    :ok = :rpc.call(node_a, ElixirTAK.Federation.Manager, :add_peer, [node_b])
    :ok = :rpc.call(node_b, ElixirTAK.Federation.Manager, :add_peer, [node_a])
    Process.sleep(1000)

    # Broadcast an SA event on node A
    event = %ElixirTAK.Protocol.CotEvent{
      uid: "loop-client-1",
      type: "a-f-G-U-C",
      how: "m-g",
      time: DateTime.utc_now(),
      start: DateTime.utc_now(),
      stale: DateTime.add(DateTime.utc_now(), 600, :second),
      point: %{lat: 33.5, lon: -111.9, hae: nil, ce: nil, le: nil},
      detail: %{callsign: "LoopTest"},
      raw_detail: "<detail><contact callsign=\"LoopTest\"/></detail>"
    }

    :rpc.call(node_a, Phoenix.PubSub, :broadcast, [
      ElixirTAK.PubSub,
      "cot:broadcast",
      {:cot_broadcast, "loop-client-1", event, "Cyan"}
    ])

    # Wait for any potential bounce
    Process.sleep(2000)

    # Node A should have sent 1 event outbound
    stats_a = :rpc.call(node_a, ElixirTAK.Federation.Manager, :get_stats, [])

    assert stats_a.events_sent == 1,
           "Node A should have sent exactly 1 event, got #{stats_a.events_sent}"

    # Node B should have received 1 event, sent 0 (not re-federated back)
    stats_b = :rpc.call(node_b, ElixirTAK.Federation.Manager, :get_stats, [])

    assert stats_b.events_received == 1,
           "Node B should have received 1 event, got #{stats_b.events_received}"

    # The event should NOT bounce back - node A should not receive it back
    assert stats_a.events_received == 0,
           "Node A should not receive its own event back, got #{stats_a.events_received}"

    LocalCluster.stop_nodes([node_a, node_b])
  end
end
