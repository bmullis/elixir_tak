defmodule ElixirTAK.Transport.GroupRoutingTest do
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

  test "same-group clients see each other", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, bravo} = connect(port)
    drain(alpha)
    drain(bravo)

    # Both are Cyan
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    assert_receives(bravo, "ALPHA-001")

    send_sa(bravo, "BRAVO-001", "BRAVO-1", "Cyan")
    assert_receives(alpha, "BRAVO-001")

    close([alpha, bravo])
  end

  test "different-group clients are isolated", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, charlie} = connect(port)

    # Identify both clients in their groups first
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    Process.sleep(100)

    # Drain any events received during identification (ungrouped clients see everything)
    drain(alpha)
    drain(charlie)

    # Now send new events - isolation should be in effect
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    Process.sleep(100)

    assert_no_data(charlie)

    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    Process.sleep(100)

    assert_no_data(alpha)

    close([alpha, charlie])
  end

  test "broadcast types cross group boundaries", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, charlie} = connect(port)

    # Identify them in different groups first
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    Process.sleep(100)
    drain(alpha)
    drain(charlie)

    # Alpha sends a chat event (b-t-f type) - should cross group boundaries
    send_event(alpha, "ALPHA-001", "b-t-f", "ALPHA-1", "Cyan")
    assert_receives(charlie, "ALPHA-001")

    close([alpha, charlie])
  end

  test "ungrouped client sees everything", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, delta} = connect(port)
    drain(alpha)
    drain(delta)

    # Alpha is Cyan, Delta has no group
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")

    # Delta is on global topic, should receive Alpha's event
    assert_receives(delta, "ALPHA-001")

    # Now Delta sends (ungrouped) - Alpha should receive via global topic
    send_sa_no_group(delta, "DELTA-001", "DELTA-1")
    assert_receives(alpha, "DELTA-001")

    close([alpha, delta])
  end

  test "client changes group", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, bravo} = connect(port)
    {:ok, charlie} = connect(port)

    # Alpha starts as Cyan, Bravo is Cyan, Charlie is Yellow
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    send_sa(bravo, "BRAVO-001", "BRAVO-1", "Cyan")
    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    Process.sleep(100)
    drain(alpha)
    drain(bravo)
    drain(charlie)

    # Alpha changes to Yellow
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Yellow")
    Process.sleep(100)
    drain(alpha)
    drain(charlie)

    # Now Charlie (Yellow) sends - Alpha (now Yellow) should receive
    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    assert_receives(alpha, "CHARLIE-001")

    # Bravo (Cyan) should NOT receive Charlie's Yellow event
    assert_no_data(bravo)

    close([alpha, bravo, charlie])
  end

  test "emergency alert crosses group boundaries", %{port: port} do
    {:ok, alpha} = connect(port)
    {:ok, charlie} = connect(port)

    # Different groups
    send_sa(alpha, "ALPHA-001", "ALPHA-1", "Cyan")
    send_sa(charlie, "CHARLIE-001", "CHARLIE-1", "Yellow")
    Process.sleep(100)
    drain(alpha)
    drain(charlie)

    # Alpha sends emergency (b-a-o-tbl) - should reach everyone
    send_event(alpha, "ALPHA-001", "b-a-o-tbl", "ALPHA-1", "Cyan")
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
    event = build_sa_event(uid, "a-f-G-U-C", callsign, group_name)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(socket, xml)
    # Small delay to let the server process the event
    Process.sleep(50)
  end

  defp send_sa_no_group(socket, uid, callsign) do
    event = build_event_no_group(uid, "a-f-G-U-C", callsign)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(socket, xml)
    Process.sleep(50)
  end

  defp send_event(socket, uid, type, callsign, group_name) do
    event = build_sa_event(uid, type, callsign, group_name)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(socket, xml)
    Process.sleep(50)
  end

  defp assert_receives(socket, expected_uid) do
    case :gen_tcp.recv(socket, 0, 3000) do
      {:ok, data} ->
        assert String.contains?(data, expected_uid),
               "Expected to find #{expected_uid} in received data: #{inspect(data)}"

      {:error, :timeout} ->
        flunk("Expected to receive event with UID #{expected_uid}, but timed out")

      {:error, reason} ->
        flunk("Recv error waiting for #{expected_uid}: #{inspect(reason)}")
    end
  end

  defp assert_no_data(socket) do
    case :gen_tcp.recv(socket, 0, 300) do
      {:error, :timeout} ->
        :ok

      {:ok, data} ->
        flunk("Expected no data but received: #{inspect(data)}")
    end
  end

  defp drain(socket) do
    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, _data} -> drain(socket)
      {:error, :timeout} -> :ok
      {:error, _} -> :ok
    end
  end

  defp build_sa_event(uid, type, callsign, group_name) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    %CotEvent{
      uid: uid,
      type: type,
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

  defp build_event_no_group(uid, type, callsign) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    %CotEvent{
      uid: uid,
      type: type,
      how: "m-g",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: 33.4942, lon: -111.9261, hae: nil, ce: nil, le: nil},
      detail: %{
        callsign: callsign,
        group: nil,
        track: %{speed: 0.0, course: 0.0}
      }
    }
  end
end
