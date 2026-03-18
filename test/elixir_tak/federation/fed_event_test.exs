defmodule ElixirTAK.Federation.FedEventTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Federation.FedEvent
  alias ElixirTAK.Protocol.CotEvent

  @point %{lat: 33.4, lon: -111.9, hae: nil, ce: nil, le: nil}

  @event %CotEvent{
    uid: "test-uid-1",
    type: "a-f-G-U-C",
    how: "m-g",
    point: @point
  }

  describe "wrap/4" do
    test "creates a FedEvent with correct fields" do
      fed = FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan")

      assert fed.event == @event
      assert fed.source_server == "SERVER-ABC"
      assert fed.hop_count == 1
      assert fed.sender_uid == "sender-1"
      assert fed.sender_group == "Cyan"
      assert %DateTime{} = fed.timestamp
    end

    test "sets timestamp to current UTC time" do
      before = DateTime.utc_now()
      fed = FedEvent.wrap(@event, "SERVER-ABC", "sender-1", nil)
      after_time = DateTime.utc_now()

      assert DateTime.compare(fed.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(fed.timestamp, after_time) in [:lt, :eq]
    end

    test "accepts nil sender_group" do
      fed = FedEvent.wrap(@event, "SERVER-ABC", "sender-1", nil)
      assert fed.sender_group == nil
    end
  end

  describe "should_forward?/1" do
    test "allows forwarding at hop_count 1" do
      fed = FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan")
      assert FedEvent.should_forward?(fed)
    end

    test "allows forwarding at hop_count 2" do
      fed = %{FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan") | hop_count: 2}
      assert FedEvent.should_forward?(fed)
    end

    test "rejects forwarding at hop_count 3" do
      fed = %{FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan") | hop_count: 3}
      refute FedEvent.should_forward?(fed)
    end

    test "rejects forwarding above max hops" do
      fed = %{FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan") | hop_count: 5}
      refute FedEvent.should_forward?(fed)
    end
  end

  describe "increment_hop/1" do
    test "increments hop_count by 1" do
      fed = FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan")
      incremented = FedEvent.increment_hop(fed)

      assert incremented.hop_count == 2
    end

    test "preserves all other fields" do
      fed = FedEvent.wrap(@event, "SERVER-ABC", "sender-1", "Cyan")
      incremented = FedEvent.increment_hop(fed)

      assert incremented.event == fed.event
      assert incremented.source_server == fed.source_server
      assert incremented.timestamp == fed.timestamp
      assert incremented.sender_uid == fed.sender_uid
      assert incremented.sender_group == fed.sender_group
    end
  end
end
