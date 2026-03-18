defmodule ElixirTAK.Protocol.NegotiationTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, Negotiation}

  describe "version_offer/0" do
    test "builds a valid version offer event" do
      offer = Negotiation.version_offer()

      assert %CotEvent{} = offer
      assert offer.type == "t-x-takp-v"
      assert offer.how == "m-g"
      assert offer.raw_detail =~ "TakProtocolSupport"
      assert offer.raw_detail =~ ~s(version="1")
    end
  end

  describe "negotiation_event?/1" do
    test "detects negotiation events" do
      assert Negotiation.negotiation_event?(%CotEvent{
               uid: "x",
               type: "t-x-takp-v",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })

      assert Negotiation.negotiation_event?(%CotEvent{
               uid: "x",
               type: "t-x-takp-q",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })

      assert Negotiation.negotiation_event?(%CotEvent{
               uid: "x",
               type: "t-x-takp-r",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })
    end

    test "rejects non-negotiation events" do
      refute Negotiation.negotiation_event?(%CotEvent{
               uid: "x",
               type: "a-f-G-U-C",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })
    end
  end

  describe "negotiation_request?/1" do
    test "detects request type" do
      assert Negotiation.negotiation_request?(%CotEvent{
               uid: "x",
               type: "t-x-takp-q",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })
    end

    test "rejects offer and response types" do
      refute Negotiation.negotiation_request?(%CotEvent{
               uid: "x",
               type: "t-x-takp-v",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })

      refute Negotiation.negotiation_request?(%CotEvent{
               uid: "x",
               type: "t-x-takp-r",
               point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil}
             })
    end
  end

  describe "requested_version/1" do
    test "extracts version from request raw_detail" do
      event = %CotEvent{
        uid: "x",
        type: "t-x-takp-q",
        point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil},
        raw_detail: ~s(<detail><TakControl><TakRequest version="1"/></TakControl></detail>)
      }

      assert Negotiation.requested_version(event) == 1
    end

    test "returns nil for missing version" do
      event = %CotEvent{
        uid: "x",
        type: "t-x-takp-q",
        point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil},
        raw_detail: "<detail><TakControl><TakRequest/></TakControl></detail>"
      }

      assert Negotiation.requested_version(event) == nil
    end

    test "returns nil for nil raw_detail" do
      event = %CotEvent{
        uid: "x",
        type: "t-x-takp-q",
        point: %{lat: 0, lon: 0, hae: nil, ce: nil, le: nil},
        raw_detail: nil
      }

      assert Negotiation.requested_version(event) == nil
    end
  end

  describe "supported_version?/1" do
    test "version 1 is supported" do
      assert Negotiation.supported_version?(1)
    end

    test "other versions are not supported" do
      refute Negotiation.supported_version?(0)
      refute Negotiation.supported_version?(2)
    end
  end

  describe "version_response/1" do
    test "builds accepted response" do
      response = Negotiation.version_response(true)

      assert response.type == "t-x-takp-r"
      assert response.raw_detail =~ ~s(status="true")
    end

    test "builds rejected response" do
      response = Negotiation.version_response(false)

      assert response.type == "t-x-takp-r"
      assert response.raw_detail =~ ~s(status="false")
    end
  end
end
