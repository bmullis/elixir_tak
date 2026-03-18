defmodule ElixirTAK.Federation.ManagerTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.Federation.{FedEvent, Manager}
  alias ElixirTAK.Protocol.CotEvent

  @pubsub ElixirTAK.PubSub
  @cot_topic "cot:broadcast"

  defmodule MockTransport do
    @moduledoc false
    @behaviour ElixirTAK.Federation.Transport

    def connect(_config), do: {:ok, :mock_peer}
    def disconnect(_peer_id), do: :ok

    def send_event(fed_event) do
      send(Process.get(:test_pid), {:transport_sent, fed_event})
      :ok
    end

    def connected_peers, do: [:mock_peer]
  end

  setup do
    # Ensure the injected ETS table doesn't exist from a previous run
    try do
      :ets.delete(:federation_injected)
    rescue
      ArgumentError -> :ok
    end

    # Start the manager with our mock transport
    Application.put_env(:elixir_tak, ElixirTAK.Federation,
      enabled: true,
      transport: MockTransport,
      peers: []
    )

    pid = start_supervised!({Manager, []})

    # Store test pid in process dictionary for the mock transport
    # The mock transport runs in the Manager's process, so we need
    # to send the test pid to the manager
    :ok

    %{manager: pid}
  end

  defp make_event(type, uid \\ "test-uid-1") do
    %CotEvent{
      uid: uid,
      type: type,
      how: "m-g",
      time: DateTime.utc_now(),
      start: DateTime.utc_now(),
      stale: DateTime.add(DateTime.utc_now(), 600, :second),
      point: %{lat: 33.5, lon: -111.9, hae: nil, ce: nil, le: nil},
      detail: %{callsign: "TestUser"},
      raw_detail: "<detail><contact callsign=\"TestUser\"/></detail>"
    }
  end

  describe "get_stats/0" do
    test "returns initial stats" do
      stats = Manager.get_stats()

      assert stats.peers_configured == 0
      assert stats.peers_connected == 0
      assert stats.events_sent == 0
      assert stats.events_received == 0
      assert is_binary(stats.server_uid)
    end
  end

  describe "list_peers/0" do
    test "returns empty map initially" do
      assert Manager.list_peers() == %{}
    end
  end

  describe "add_peer/1 and remove_peer/1" do
    test "adds and removes a peer" do
      :ok = Manager.add_peer(:some_node)
      peers = Manager.list_peers()
      assert Map.has_key?(peers, :mock_peer)

      :ok = Manager.remove_peer(:mock_peer)
      assert Manager.list_peers() == %{}
    end
  end

  describe "inbound federation events" do
    test "accepts valid federated event and broadcasts locally" do
      Phoenix.PubSub.subscribe(@pubsub, @cot_topic)

      event = make_event("a-f-G-U-C")

      fed_event = %FedEvent{
        event: event,
        source_server: "REMOTE-SERVER-1",
        hop_count: 1,
        timestamp: DateTime.utc_now(),
        sender_uid: "remote-client-1",
        sender_group: "Cyan"
      }

      send(Process.whereis(Manager), {:fed_event, fed_event})

      assert_receive {:cot_broadcast, "remote-client-1", ^event, "Cyan"}, 1000
    end

    test "drops event from own server (loop prevention)" do
      Phoenix.PubSub.subscribe(@pubsub, @cot_topic)

      server_uid = Manager.get_stats().server_uid
      event = make_event("a-f-G-U-C")

      fed_event = %FedEvent{
        event: event,
        source_server: server_uid,
        hop_count: 1,
        timestamp: DateTime.utc_now(),
        sender_uid: "my-client",
        sender_group: "Cyan"
      }

      send(Process.whereis(Manager), {:fed_event, fed_event})

      refute_receive {:cot_broadcast, _, _, _}, 200
    end

    test "drops event at hop limit" do
      Phoenix.PubSub.subscribe(@pubsub, @cot_topic)

      event = make_event("a-f-G-U-C")

      fed_event = %FedEvent{
        event: event,
        source_server: "REMOTE-SERVER-2",
        hop_count: 3,
        timestamp: DateTime.utc_now(),
        sender_uid: "remote-client-2",
        sender_group: "Yellow"
      }

      send(Process.whereis(Manager), {:fed_event, fed_event})

      refute_receive {:cot_broadcast, _, _, _}, 200
    end

    test "updates inbound stats on accepted event" do
      event = make_event("a-f-G-U-C")

      fed_event = %FedEvent{
        event: event,
        source_server: "REMOTE-SERVER-3",
        hop_count: 1,
        timestamp: DateTime.utc_now(),
        sender_uid: "remote-client-3",
        sender_group: "Cyan"
      }

      send(Process.whereis(Manager), {:fed_event, fed_event})
      Process.sleep(50)

      stats = Manager.get_stats()
      assert stats.events_received == 1
    end
  end

  describe "recently_injected loop prevention" do
    test "injected event is not re-federated on outbound path" do
      # Simulate an inbound event (marks it as injected)
      event = make_event("a-f-G-U-C", "loop-test-uid")

      fed_event = %FedEvent{
        event: event,
        source_server: "REMOTE-SERVER-4",
        hop_count: 1,
        timestamp: DateTime.utc_now(),
        sender_uid: "remote-client-4",
        sender_group: "Cyan"
      }

      manager_pid = Process.whereis(Manager)
      send(manager_pid, {:fed_event, fed_event})

      # Wait for it to be processed and marked as injected
      Process.sleep(50)

      # Now the Manager will receive this same event back via PubSub
      # (because it broadcast it). The cot_broadcast handler should
      # recognize it as recently_injected and skip federation.
      # We verify by checking stats - events_sent should stay 0
      stats = Manager.get_stats()
      assert stats.events_sent == 0
    end
  end

  describe "policy filtering" do
    test "non-federable types are not forwarded" do
      # t-x-takp type should not be federated
      event = make_event("t-x-takp-q")

      # Broadcast as if from a local client
      Phoenix.PubSub.broadcast(
        @pubsub,
        @cot_topic,
        {:cot_broadcast, "local-client", event, "Cyan"}
      )

      Process.sleep(50)
      stats = Manager.get_stats()
      assert stats.events_sent == 0
    end
  end

  describe "peer lifecycle" do
    test "handles peer_connected notification" do
      send(Process.whereis(Manager), {:peer_connected, :test_node})
      Process.sleep(50)

      peers = Manager.list_peers()
      assert Map.has_key?(peers, :test_node)
      assert peers[:test_node].status == :connected
    end

    test "handles peer_disconnected notification" do
      send(Process.whereis(Manager), {:peer_connected, :test_node2})
      Process.sleep(50)

      send(Process.whereis(Manager), {:peer_disconnected, :test_node2})
      Process.sleep(50)

      peers = Manager.list_peers()
      assert peers[:test_node2].status == :disconnected
    end
  end
end
