defmodule ElixirTAK.Protocol.ChatParserTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{ChatParser, CotEvent}

  @raw_detail """
  <detail>\
  <__chat parent="RootContactGroup" groupOwner="false" \
  chatroom="All Chat Rooms" id="All Chat Rooms" \
  senderCallsign="ALPHA-1">\
  <chatgrp uid0="ALPHA-001" uid1="All Chat Rooms" id="All Chat Rooms"/>\
  </__chat>\
  <link uid="ALPHA-001" type="a-f-G-U-C" relation="p-p"/>\
  <remarks source="BAO.F.ATAK.ALPHA-001" sourceID="ALPHA-001" \
  to="All Chat Rooms" time="2024-01-15T12:00:00Z">Hello everyone</remarks>\
  </detail>
  """

  defp chat_event(overrides \\ %{}) do
    now = DateTime.utc_now()

    defaults = %{
      uid: "GeoChat.ALPHA-001.All Chat Rooms.AABBCCDD",
      type: "b-t-f",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: DateTime.add(now, 120, :second),
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: nil, group: nil, track: nil},
      raw_detail: @raw_detail
    }

    struct!(CotEvent, Map.merge(defaults, overrides))
  end

  describe "parse/1" do
    test "extracts sender, chatroom, message, and sender_uid" do
      assert {:ok, msg} = ChatParser.parse(chat_event())
      assert msg.sender == "ALPHA-1"
      assert msg.chatroom == "All Chat Rooms"
      assert msg.message == "Hello everyone"
      assert msg.sender_uid == "ALPHA-001"
      assert msg.uid == "GeoChat.ALPHA-001.All Chat Rooms.AABBCCDD"
      assert %DateTime{} = msg.time
    end

    test "returns :error for non-chat event type" do
      assert :error = ChatParser.parse(chat_event(%{type: "a-f-G-U-C"}))
    end

    test "returns :error when raw_detail is nil" do
      assert :error = ChatParser.parse(chat_event(%{raw_detail: nil}))
    end

    test "returns :error when senderCallsign is missing" do
      raw = ~s(<detail><remarks>Hello</remarks></detail>)
      assert :error = ChatParser.parse(chat_event(%{raw_detail: raw}))
    end

    test "returns :error when remarks element is missing" do
      raw = ~s(<detail><__chat senderCallsign="X" chatroom="Room"></__chat></detail>)
      assert :error = ChatParser.parse(chat_event(%{raw_detail: raw}))
    end

    test "handles b-t-f subtype variants" do
      assert {:ok, msg} = ChatParser.parse(chat_event(%{type: "b-t-f-d"}))
      assert msg.sender == "ALPHA-1"
    end
  end

  describe "parse!/1" do
    test "returns map on success" do
      msg = ChatParser.parse!(chat_event())
      assert msg.sender == "ALPHA-1"
      assert msg.message == "Hello everyone"
    end

    test "returns nil on failure" do
      assert nil == ChatParser.parse!(chat_event(%{type: "a-f-G-U-C"}))
    end
  end

  describe "extract_chatroom/1" do
    test "extracts chatroom from raw XML" do
      assert {:ok, "All Chat Rooms"} = ChatParser.extract_chatroom(@raw_detail)
    end

    test "returns :error when no chatroom attribute" do
      assert :error = ChatParser.extract_chatroom("<detail><remarks>Hi</remarks></detail>")
    end
  end
end
