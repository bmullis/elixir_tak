defmodule ElixirTAK.Federation.Transport.BEAMTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Federation.FedEvent
  alias ElixirTAK.Federation.Transport.BEAM
  alias ElixirTAK.Protocol.CotEvent

  @pg_scope ElixirTAK.PG
  @pg_group :federation_managers

  setup do
    # Ensure the pg scope is started for tests
    start_supervised!(%{
      id: @pg_scope,
      start: {:pg, :start_link, [@pg_scope]}
    })

    # Start the transport with self() as the manager
    transport =
      start_supervised!({BEAM, [manager: self()]})

    %{transport: transport}
  end

  describe "connected_peers/0" do
    test "returns empty list when no remote nodes are connected" do
      assert BEAM.connected_peers() == []
    end

    test "does not include the local node in peers" do
      # The transport itself joins the pg group, but since it's on the local
      # node it should not appear in connected_peers
      assert BEAM.connected_peers() == []
    end
  end

  describe "send_event/1" do
    test "returns :ok even with no remote peers" do
      event = build_fed_event()
      assert :ok = BEAM.send_event(event)
    end

    test "sends to pg group members on other nodes (simulated via local member)" do
      # We cannot truly test cross-node delivery in a unit test, but we can
      # verify the function iterates pg members and skips local ones.
      # Since all members are local in a single-node test, no messages are sent.
      event = build_fed_event()
      assert :ok = BEAM.send_event(event)
      refute_received {:fed_event, _}
    end
  end

  describe "connect/1" do
    test "returns error when node is not alive" do
      # In a non-distributed test environment, Node.connect returns :ignored
      assert {:error, _reason} = BEAM.connect(:nonexistent@nowhere)
    end
  end

  describe "disconnect/1" do
    test "returns :ok for any node" do
      assert :ok = BEAM.disconnect(:nonexistent@nowhere)
    end
  end

  describe "node monitoring" do
    test "transport joins the pg group on startup", %{transport: transport} do
      members = :pg.get_members(@pg_scope, @pg_group)
      assert transport in members
    end
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_fed_event do
    event = %CotEvent{
      uid: "test-uid-123",
      type: "a-f-G-U-C",
      time: DateTime.utc_now(),
      start: DateTime.utc_now(),
      stale: DateTime.add(DateTime.utc_now(), 60, :second),
      point: %{lat: 33.4942, lon: -111.9261, hae: 0.0, ce: nil, le: nil},
      detail: %{}
    }

    %FedEvent{
      event: event,
      source_server: "ELIXIRTAK-TEST",
      hop_count: 1,
      timestamp: DateTime.utc_now(),
      sender_uid: "test-uid-123",
      sender_group: "Cyan"
    }
  end
end
