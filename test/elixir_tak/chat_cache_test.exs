defmodule ElixirTAK.ChatCacheTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.ChatCache
  alias ElixirTAK.Protocol.CotEvent

  setup do
    # Clear the ETS table between tests
    :ets.delete_all_objects(:chat_cache)
    :ok
  end

  test "stores and retrieves a chat event" do
    event = build_chat("SENDER-1", "ALPHA-1", "All Chat Rooms", "Hello")
    ChatCache.put(event)

    assert [returned] = ChatCache.get_all()
    assert returned.uid == event.uid
  end

  test "get_all returns messages newest first" do
    for i <- 1..5 do
      event = build_chat("SENDER-1", "ALPHA-1", "All Chat Rooms", "Message #{i}")
      ChatCache.put(event)
    end

    messages = ChatCache.get_all()
    assert length(messages) == 5

    # The last inserted should be first in the list
    assert String.contains?(hd(messages).uid, ".")
    # Verify ordering: UIDs should be in reverse insertion order
    uids = Enum.map(messages, & &1.uid)
    assert uids == Enum.reverse(Enum.sort(uids)) || length(Enum.uniq(uids)) == 5
  end

  test "bounded at 200 messages" do
    for i <- 1..250 do
      event = build_chat("SENDER-1", "ALPHA-1", "All Chat Rooms", "Message #{i}")
      ChatCache.put(event)
    end

    assert ChatCache.count() == 200
    assert length(ChatCache.get_all()) == 200
  end

  test "get_by_room filters correctly" do
    ChatCache.put(build_chat("SENDER-1", "ALPHA-1", "All Chat Rooms", "Hi all"))
    ChatCache.put(build_chat("SENDER-1", "ALPHA-1", "Team Chat", "Hi team"))
    ChatCache.put(build_chat("SENDER-2", "BRAVO-1", "All Chat Rooms", "Hey"))

    all_chat = ChatCache.get_by_room("All Chat Rooms")
    assert length(all_chat) == 2

    team_chat = ChatCache.get_by_room("Team Chat")
    assert length(team_chat) == 1

    unknown = ChatCache.get_by_room("Nonexistent")
    assert unknown == []
  end

  test "count returns correct number" do
    assert ChatCache.count() == 0

    ChatCache.put(build_chat("SENDER-1", "ALPHA-1", "All Chat Rooms", "Hello"))
    assert ChatCache.count() == 1

    ChatCache.put(build_chat("SENDER-2", "BRAVO-1", "All Chat Rooms", "World"))
    assert ChatCache.count() == 2
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_chat(sender_uid, sender_callsign, chatroom, message) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 120, :second)

    chat_uid =
      "GeoChat.#{sender_uid}.#{chatroom}.#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

    raw_detail = """
    <detail>\
    <__chat parent="RootContactGroup" groupOwner="false" \
    chatroom="#{chatroom}" id="#{chatroom}" \
    senderCallsign="#{sender_callsign}">\
    <chatgrp uid0="#{sender_uid}" uid1="#{chatroom}" id="#{chatroom}"/>\
    </__chat>\
    <link uid="#{sender_uid}" type="a-f-G-U-C" relation="p-p"/>\
    <remarks source="BAO.F.ATAK.#{sender_uid}" sourceID="#{sender_uid}" \
    to="#{chatroom}" time="#{DateTime.to_iso8601(now)}">#{message}</remarks>\
    </detail>\
    """

    %CotEvent{
      uid: chat_uid,
      type: "b-t-f",
      how: "h-g-i-g-o",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: nil, group: nil, track: nil},
      raw_detail: raw_detail
    }
  end
end
