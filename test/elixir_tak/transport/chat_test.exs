defmodule ElixirTAK.Transport.ChatTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.Protocol.{CotEncoder, CotEvent}

  setup do
    # Clear all caches to avoid stale data from other tests
    :ets.delete_all_objects(:sa_cache)
    :ets.delete_all_objects(:chat_cache)
    :ets.delete_all_objects(:marker_cache)
    :ets.delete_all_objects(:shape_cache)

    {:ok, pid} =
      start_supervised({ThousandIsland, port: 0, handler_module: ElixirTAK.Transport.CotHandler})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{port: port}
  end

  test "client A sends chat, client B receives it", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, bravo} = connect(port)

    # Identify both clients with SA first
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    send_sa(bravo, "BRAVO-001", "BRAVO-1", "Cyan")
    Process.sleep(100)
    drain(alpha)
    drain(bravo)

    # Alpha sends chat
    send_chat(alpha, "ALPHA-001", "ALPHA-1", "All Chat Rooms", "Hello everyone")
    assert_receives(bravo, "Hello everyone")

    close([alpha, bravo])
  end

  test "late joiner receives chat history", %{port: port} do
    {:ok, alpha} = connect(port)

    # Identify and send chat
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    Process.sleep(50)
    drain(alpha)

    send_chat(alpha, "ALPHA-001", "ALPHA-1", "All Chat Rooms", "Before charlie joined")
    Process.sleep(100)

    # Charlie connects late
    {:ok, charlie} = connect(port)
    Process.sleep(200)

    # Charlie should receive cached chat history
    data = recv_all(charlie, 2000)

    assert String.contains?(data, "Before charlie joined"),
           "Late joiner should receive chat history, got: #{inspect(data)}"

    close([alpha, charlie])
  end

  test "chat crosses group boundaries", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, charlie} = connect(port)

    # Different groups
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    Process.sleep(100)
    drain(alpha)
    drain(charlie)

    # Alpha sends chat - should reach Charlie despite different group
    send_chat(alpha, "ALPHA-001", "ALPHA-1", "All Chat Rooms", "Cross group chat")
    assert_receives(charlie, "ALPHA-001")

    close([alpha, charlie])
  end

  # -- Helpers ---------------------------------------------------------------

  defp connect(port) do
    :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw])
  end

  defp close(sockets) when is_list(sockets) do
    Enum.each(sockets, &:gen_tcp.close/1)
  end

  defp send_sa(socket, uid, callsign, group_name) do
    event = build_sa_event(uid, callsign, group_name)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(socket, xml)
    Process.sleep(50)
  end

  defp send_chat(socket, sender_uid, sender_callsign, chatroom, message) do
    event = build_chat_event(sender_uid, sender_callsign, chatroom, message)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(socket, xml)
    Process.sleep(50)
  end

  defp assert_receives(socket, expected_content) do
    case :gen_tcp.recv(socket, 0, 3000) do
      {:ok, data} ->
        assert String.contains?(data, expected_content),
               "Expected to find #{inspect(expected_content)} in: #{inspect(data)}"

      {:error, :timeout} ->
        flunk("Expected to receive data containing #{inspect(expected_content)}, but timed out")

      {:error, reason} ->
        flunk("Recv error: #{inspect(reason)}")
    end
  end

  defp drain(socket) do
    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, _data} -> drain(socket)
      {:error, :timeout} -> :ok
      {:error, _} -> :ok
    end
  end

  defp recv_all(socket, timeout) do
    recv_all(socket, timeout, <<>>)
  end

  defp recv_all(socket, timeout, acc) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} -> recv_all(socket, timeout, acc <> data)
      {:error, :timeout} -> acc
      {:error, _} -> acc
    end
  end

  defp build_sa_event(uid, callsign, group_name) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    %CotEvent{
      uid: uid,
      type: "a-f-G-U-C",
      how: "m-g",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 33.4942, lon: -111.9261, hae: nil, ce: nil, le: nil},
      detail: %{
        callsign: callsign,
        group: %{name: group_name, role: "Team Member"},
        track: %{speed: 0.0, course: 0.0}
      }
    }
  end

  defp build_chat_event(sender_uid, sender_callsign, chatroom, message) do
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
