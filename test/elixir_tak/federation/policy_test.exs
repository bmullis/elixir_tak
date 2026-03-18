defmodule ElixirTAK.Federation.PolicyTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Federation.Policy
  alias ElixirTAK.Protocol.CotEvent

  @point %{lat: 33.4, lon: -111.9, hae: nil, ce: nil, le: nil}

  defp event(type) do
    %CotEvent{uid: "test-1", type: type, point: @point}
  end

  describe "federate?/1" do
    test "federates friendly SA" do
      assert Policy.federate?(event("a-f-G-U-C"))
    end

    test "federates hostile SA" do
      assert Policy.federate?(event("a-h-G"))
    end

    test "federates neutral SA" do
      assert Policy.federate?(event("a-n-G"))
    end

    test "federates unknown SA" do
      assert Policy.federate?(event("a-u-G"))
    end

    test "federates chat messages" do
      assert Policy.federate?(event("b-t-f"))
    end

    test "federates chat with subtypes" do
      assert Policy.federate?(event("b-t-f-d"))
    end

    test "federates emergency alerts" do
      assert Policy.federate?(event("b-a-o-tbl"))
    end

    test "federates geofence alerts" do
      assert Policy.federate?(event("b-a-g"))
    end

    test "federates marker points" do
      assert Policy.federate?(event("b-m-p-s-p-i"))
    end

    test "federates routes" do
      assert Policy.federate?(event("b-m-r"))
    end

    test "federates shapes/drawings" do
      assert Policy.federate?(event("u-d-f"))
    end

    test "rejects protocol negotiation types" do
      refute Policy.federate?(event("t-x-takp-v"))
    end

    test "rejects unknown types" do
      refute Policy.federate?(event("z-something"))
    end

    test "rejects non-chat b-t types" do
      refute Policy.federate?(event("b-t-a"))
    end
  end

  describe "accept?/2" do
    test "accepts any event from any source" do
      assert Policy.accept?(event("a-f-G-U-C"), "PEER-SERVER-1")
    end
  end
end
