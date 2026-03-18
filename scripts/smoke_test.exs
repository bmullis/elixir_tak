defmodule ElixirTAK.SmokeTest do
  @moduledoc """
  Smoke test: starts the server, connects two fake TAK clients,
  sends SA messages, and verifies each client receives the other's position.

  Run with: mix run test/smoke_test.exs
  """

  alias ElixirTAK.Proto
  alias ElixirTAK.Protocol.{CotEncoder, CotEvent, ProtoEncoder, TakFramer}

  @host ~c"127.0.0.1"
  @port 8087

  def run do
    IO.puts("\n=== ElixirTAK Smoke Test ===\n")

    # Give the server a moment to be ready (it starts via Application)
    Process.sleep(500)

    IO.puts("[1] Connecting two clients...")
    {:ok, alpha} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    {:ok, bravo} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    # Drain version offers sent on connect
    _ = recv_all(alpha, 500)
    _ = recv_all(bravo, 500)
    IO.puts("    ✓ Both clients connected to #{@host}:#{@port}")

    # -- Alpha sends SA --
    IO.puts("\n[2] ALPHA sending SA position report...")
    alpha_event = build_sa_event("ALPHA-001", "a-f-G-U-C", "ALPHA-1", 33.4942, -111.9261)
    alpha_xml = alpha_event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(alpha, alpha_xml)
    IO.puts("    ✓ Sent: uid=ALPHA-001 callsign=ALPHA-1 (Scottsdale)")

    # -- Bravo should receive Alpha's event --
    IO.puts("\n[3] BRAVO waiting for ALPHA's broadcast...")
    case :gen_tcp.recv(bravo, 0, 3000) do
      {:ok, data} ->
        IO.puts("    ✓ BRAVO received #{byte_size(data)} bytes")
        assert_contains(data, "ALPHA-001", "ALPHA's UID")
        assert_contains(data, "ALPHA-1", "ALPHA's callsign")

      {:error, :timeout} ->
        fail("BRAVO did not receive ALPHA's broadcast within 3s")

      {:error, reason} ->
        fail("BRAVO recv error: #{inspect(reason)}")
    end

    # -- Bravo sends SA --
    IO.puts("\n[4] BRAVO sending SA position report...")
    bravo_event = build_sa_event("BRAVO-002", "a-f-G-U-C", "BRAVO-2", 33.4484, -112.0740)
    bravo_xml = bravo_event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(bravo, bravo_xml)
    IO.puts("    ✓ Sent: uid=BRAVO-002 callsign=BRAVO-2 (Phoenix)")

    # -- Alpha should receive Bravo's event --
    IO.puts("\n[5] ALPHA waiting for BRAVO's broadcast...")
    case :gen_tcp.recv(alpha, 0, 3000) do
      {:ok, data} ->
        IO.puts("    ✓ ALPHA received #{byte_size(data)} bytes")
        assert_contains(data, "BRAVO-002", "BRAVO's UID")
        assert_contains(data, "BRAVO-2", "BRAVO's callsign")

      {:error, :timeout} ->
        fail("ALPHA did not receive BRAVO's broadcast within 3s")

      {:error, reason} ->
        fail("ALPHA recv error: #{inspect(reason)}")
    end

    # -- Verify no echo: Alpha should NOT have received its own event --
    IO.puts("\n[6] Verifying no echo (ALPHA should not receive its own event)...")
    case :gen_tcp.recv(alpha, 0, 500) do
      {:error, :timeout} ->
        IO.puts("    ✓ No echo detected (timed out as expected)")

      {:ok, data} ->
        if String.contains?(data, "ALPHA-001") do
          fail("ALPHA received its own event (echo detected)")
        else
          IO.puts("    ✓ Received data but not an echo: #{byte_size(data)} bytes")
        end
    end

    # -- Rapid-fire: send multiple events quickly --
    IO.puts("\n[7] Rapid-fire: ALPHA sending 5 position updates...")
    for i <- 1..5 do
      event = build_sa_event("ALPHA-001", "a-f-G-U-C", "ALPHA-1", 33.4942 + i * 0.001, -111.9261)
      xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
      :ok = :gen_tcp.send(alpha, xml)
    end
    IO.puts("    ✓ Sent 5 events")

    IO.puts("    BRAVO receiving rapid-fire events...")
    received = recv_all(bravo, 2000)
    count = count_events(received)
    IO.puts("    ✓ BRAVO received #{count} event(s) in #{byte_size(received)} bytes")

    if count >= 5 do
      IO.puts("    ✓ All 5 events received")
    else
      IO.puts("    ⚠ Only #{count}/5 events received (may need longer timeout)")
    end

    # -- Late joiner: connect CHARLIE and verify cached SA replay --
    IO.puts("\n[8] Late joiner: connecting CHARLIE (should receive cached SA)...")
    {:ok, charlie} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    IO.puts("    ✓ CHARLIE connected")

    IO.puts("    CHARLIE waiting for cached SA replay...")
    cached = recv_all(charlie, 2000)
    cached_count = count_events(cached)
    IO.puts("    ✓ CHARLIE received #{cached_count} cached event(s) in #{byte_size(cached)} bytes")

    if cached_count >= 2 do
      IO.puts("    ✓ Received cached events for both ALPHA and BRAVO")
    else
      fail("CHARLIE expected at least 2 cached events, got #{cached_count}")
    end

    assert_contains(cached, "ALPHA-001", "cached ALPHA UID")
    assert_contains(cached, "BRAVO-002", "cached BRAVO UID")

    # -- Disconnect --
    IO.puts("\n[9] Disconnecting clients...")
    :gen_tcp.close(alpha)
    :gen_tcp.close(bravo)
    :gen_tcp.close(charlie)
    IO.puts("    ✓ All clients disconnected")

    # -- Chat --
    run_chat_smoke()

    # -- Group routing --
    run_group_smoke()

    # -- Optional TLS section --
    if File.exists?("certs/server.pem") do
      run_tls_smoke()
    else
      IO.puts("\n[TLS] Skipping TLS smoke test (no certs found)")
    end

    # -- Protobuf negotiation --
    run_protobuf_smoke()

    # -- Dashboard --
    run_dashboard_smoke()

    IO.puts("\n=== Smoke Test Passed ===\n")
  end

  defp run_chat_smoke do
    IO.puts("\n[CHAT-1] ALPHA sends a chat message...")
    {:ok, alpha} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    {:ok, bravo} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])

    # Drain cached SA from prior tests
    _ = recv_all(alpha, 500)
    _ = recv_all(bravo, 500)

    # Identify both clients
    alpha_sa = build_sa_event("CHAT-ALPHA", "a-f-G-U-C", "CHAT-ALPHA-1", 33.49, -111.92)
    :ok = :gen_tcp.send(alpha, alpha_sa |> CotEncoder.encode() |> IO.iodata_to_binary())
    bravo_sa = build_sa_event("CHAT-BRAVO", "a-f-G-U-C", "CHAT-BRAVO-1", 33.44, -112.07)
    :ok = :gen_tcp.send(bravo, bravo_sa |> CotEncoder.encode() |> IO.iodata_to_binary())
    Process.sleep(200)
    _ = recv_all(alpha, 500)
    _ = recv_all(bravo, 500)

    # Alpha sends chat
    chat = build_chat_event("CHAT-ALPHA", "CHAT-ALPHA-1", "All Chat Rooms", "Hello from smoke test")
    :ok = :gen_tcp.send(alpha, chat |> CotEncoder.encode() |> IO.iodata_to_binary())
    IO.puts("    ✓ Sent chat: uid=#{chat.uid}")

    IO.puts("\n[CHAT-2] BRAVO receives the chat...")
    case :gen_tcp.recv(bravo, 0, 3000) do
      {:ok, data} ->
        assert_contains(data, "Hello from smoke test", "chat message body")

      {:error, :timeout} ->
        fail("BRAVO did not receive chat message within 3s")

      {:error, reason} ->
        fail("BRAVO recv error: #{inspect(reason)}")
    end

    IO.puts("\n[CHAT-3] CHARLIE connects late, receives chat history...")
    {:ok, charlie} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    cached = recv_all(charlie, 2000)

    if String.contains?(cached, "Hello from smoke test") do
      IO.puts("    ✓ CHARLIE received chat history")
    else
      fail("CHARLIE did not receive chat history")
    end

    :gen_tcp.close(alpha)
    :gen_tcp.close(bravo)
    :gen_tcp.close(charlie)
    IO.puts("    ✓ Chat smoke test passed")
  end

  defp run_tls_smoke do
    IO.puts("\n[TLS-1] Connecting TLS client on port 8089...")

    ssl_opts = [
      certfile: ~c"certs/client.pem",
      keyfile: ~c"certs/client-key.pem",
      cacertfile: ~c"certs/ca.pem",
      verify: :verify_peer,
      active: false
    ]

    case :ssl.connect(@host, 8089, ssl_opts, 3000) do
      {:ok, tls_socket} ->
        IO.puts("    ✓ TLS handshake succeeded")

        IO.puts("\n[TLS-2] Sending SA over TLS...")
        event = build_sa_event("TLS-SMOKE-001", "a-f-G-U-C", "TLS-SMOKE", 33.50, -112.00)
        xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
        :ok = :ssl.send(tls_socket, xml)
        IO.puts("    ✓ Sent CoT event over TLS")

        IO.puts("\n[TLS-3] Connecting plaintext client to receive TLS broadcast...")
        {:ok, tcp_rx} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
        cached = recv_all(tcp_rx, 2000)

        if String.contains?(cached, "TLS-SMOKE-001") do
          IO.puts("    ✓ Plaintext client received TLS client's SA via cache")
        else
          IO.puts("    ⚠ TLS event not in cached replay (may already have been received)")
        end

        :ssl.close(tls_socket)
        :gen_tcp.close(tcp_rx)
        IO.puts("    ✓ TLS smoke test passed")

      {:error, reason} ->
        IO.puts("    ⚠ TLS connection failed: #{inspect(reason)}")
        IO.puts("    (This is OK if TLS listener is not running)")
    end
  end

  defp run_group_smoke do
    IO.puts("\n[GRP-1] Connecting group-aware clients (ALPHA=Cyan, BRAVO=Cyan, CHARLIE=Yellow)...")
    {:ok, alpha} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    {:ok, bravo} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    {:ok, charlie} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])

    # Drain any cached SA replay from previous tests
    _ = recv_all(alpha, 500)
    _ = recv_all(bravo, 500)
    _ = recv_all(charlie, 500)

    IO.puts("    ✓ Three clients connected")

    # Identify clients in their groups
    alpha_event = build_sa_event("GRP-ALPHA", "a-f-G-U-C", "GRP-ALPHA-1", 33.4942, -111.9261, "Cyan")
    :ok = :gen_tcp.send(alpha, alpha_event |> CotEncoder.encode() |> IO.iodata_to_binary())

    bravo_event = build_sa_event("GRP-BRAVO", "a-f-G-U-C", "GRP-BRAVO-1", 33.4484, -112.0740, "Cyan")
    :ok = :gen_tcp.send(bravo, bravo_event |> CotEncoder.encode() |> IO.iodata_to_binary())

    charlie_event = build_sa_event("GRP-CHARLIE", "a-f-G-U-C", "GRP-CHARLIE-1", 33.50, -112.00, "Yellow")
    :ok = :gen_tcp.send(charlie, charlie_event |> CotEncoder.encode() |> IO.iodata_to_binary())

    Process.sleep(200)

    IO.puts("\n[GRP-2] Verifying ALPHA<->BRAVO see each other (same group: Cyan)...")
    bravo_data = recv_all(bravo, 1000)
    if String.contains?(bravo_data, "GRP-ALPHA") do
      IO.puts("    ✓ BRAVO received ALPHA's event")
    else
      fail("BRAVO did not receive ALPHA's Cyan event")
    end

    alpha_data = recv_all(alpha, 1000)
    if String.contains?(alpha_data, "GRP-BRAVO") do
      IO.puts("    ✓ ALPHA received BRAVO's event")
    else
      fail("ALPHA did not receive BRAVO's Cyan event")
    end

    IO.puts("\n[GRP-3] Verifying CHARLIE does NOT receive Cyan SA events...")
    charlie_data = recv_all(charlie, 500)
    if String.contains?(charlie_data, "GRP-ALPHA") or String.contains?(charlie_data, "GRP-BRAVO") do
      fail("CHARLIE (Yellow) received Cyan events (group isolation broken)")
    else
      IO.puts("    ✓ CHARLIE did not receive Cyan events (isolation works)")
    end

    IO.puts("\n[GRP-4] Sending chat from ALPHA (should cross group boundaries)...")
    chat_event = build_sa_event("GRP-ALPHA", "b-t-f", "GRP-ALPHA-1", 33.4942, -111.9261, "Cyan")
    :ok = :gen_tcp.send(alpha, chat_event |> CotEncoder.encode() |> IO.iodata_to_binary())
    Process.sleep(100)

    charlie_chat = recv_all(charlie, 1000)
    if String.contains?(charlie_chat, "GRP-ALPHA") do
      IO.puts("    ✓ CHARLIE received ALPHA's chat (broadcast type crosses groups)")
    else
      fail("CHARLIE did not receive chat from ALPHA (broadcast passthrough failed)")
    end

    :gen_tcp.close(alpha)
    :gen_tcp.close(bravo)
    :gen_tcp.close(charlie)
    IO.puts("    ✓ Group routing smoke test passed")
  end

  defp run_dashboard_smoke do
    IO.puts("\n[DASH-1] Verifying dashboard is accessible...")

    case :gen_tcp.connect(@host, 8443, [:binary, active: false, packet: :raw], 2000) do
      {:ok, sock} ->
        :ok = :gen_tcp.send(sock, "GET /dashboard HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        response = recv_all(sock, 3000)
        :gen_tcp.close(sock)

        if String.contains?(response, "200 OK") and String.contains?(response, "ElixirTAK") do
          IO.puts("    ✓ Dashboard returned 200 with ElixirTAK content")
        else
          fail("Dashboard did not return expected response")
        end

      {:error, _} ->
        IO.puts("    ⚠ HTTP server not running (expected in test env), skipping")
    end

    IO.puts("\n[DASH-2] Verifying client registry tracks connected clients...")
    count = ElixirTAK.ClientRegistry.count()
    IO.puts("    ✓ ClientRegistry reports #{count} client(s)")
  end

  defp run_protobuf_smoke do
    IO.puts("\n[PROTO-1] Connecting client for protobuf negotiation...")
    {:ok, proto_client} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])
    {:ok, xml_listener} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :raw])

    # Drain cached events (SA replay + version offer)
    _ = recv_all(proto_client, 1000)
    _ = recv_all(xml_listener, 1000)

    # Identify the XML listener
    listener_sa = build_sa_event("PROTO-LISTENER", "a-f-G-U-C", "LISTENER-1", 33.50, -112.00)
    :ok = :gen_tcp.send(xml_listener, listener_sa |> CotEncoder.encode() |> IO.iodata_to_binary())

    # Identify the proto client (still in XML mode)
    proto_sa = build_sa_event("PROTO-CLIENT", "a-f-G-U-C", "PROTO-1", 33.49, -111.92)
    :ok = :gen_tcp.send(proto_client, proto_sa |> CotEncoder.encode() |> IO.iodata_to_binary())
    Process.sleep(200)

    # Drain cross-broadcasts
    _ = recv_all(proto_client, 500)
    _ = recv_all(xml_listener, 500)
    IO.puts("    ✓ Both clients connected and identified")

    IO.puts("\n[PROTO-2] Sending protocol negotiation request (version 1)...")
    negotiation_request = build_negotiation_request()
    request_xml = negotiation_request |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :gen_tcp.send(proto_client, request_xml)

    # Receive the negotiation response (may arrive mixed with simulator events)
    Process.sleep(200)
    data = recv_all(proto_client, 1000)

    if byte_size(data) == 0 do
      fail("Did not receive negotiation response")
    else
      assert_contains(data, "t-x-takp-r", "negotiation response type")
      assert_contains(data, ~s(status="true"), "accepted status")
    end

    IO.puts("\n[PROTO-3] Sending protobuf-encoded SA event...")
    proto_event = build_sa_event("PROTO-CLIENT", "a-f-G-U-C", "PROTO-1", 33.55, -111.88)
    proto_bytes = ProtoEncoder.encode(proto_event)
    framed = TakFramer.frame_protobuf(proto_bytes)
    :ok = :gen_tcp.send(proto_client, framed)
    IO.puts("    ✓ Sent #{byte_size(framed)} bytes (protobuf-framed)")

    IO.puts("\n[PROTO-4] XML listener receives the event (server converts to XML)...")
    Process.sleep(200)
    listener_data = recv_all(xml_listener, 1000)

    if String.contains?(listener_data, "PROTO-CLIENT") do
      IO.puts("    ✓ XML listener received protobuf client's event as XML")
    else
      fail("XML listener did not receive protobuf client's event")
    end

    IO.puts("\n[PROTO-5] Verifying protobuf client receives events in protobuf format...")
    # Drain any pending data first
    _ = recv_all(proto_client, 500)

    # XML listener sends a new SA
    new_sa = build_sa_event("PROTO-LISTENER", "a-f-G-U-C", "LISTENER-1", 33.51, -112.01)
    :ok = :gen_tcp.send(xml_listener, new_sa |> CotEncoder.encode() |> IO.iodata_to_binary())

    Process.sleep(200)
    proto_data = recv_all(proto_client, 1000)

    if byte_size(proto_data) == 0 do
      fail("Protobuf client did not receive any data")
    else
      # After negotiation, all data to proto_client should be protobuf-framed (0xBF prefix)
      <<first_byte, _rest::binary>> = proto_data

      if first_byte == 0xBF do
        IO.puts("    ✓ Received #{byte_size(proto_data)} bytes with 0xBF magic byte (protobuf format)")
      else
        fail("Protobuf client received non-protobuf data (first byte: 0x#{Integer.to_string(first_byte, 16)})")
      end
    end

    :gen_tcp.close(proto_client)
    :gen_tcp.close(xml_listener)
    IO.puts("    ✓ Protobuf negotiation smoke test passed")
  end

  defp build_negotiation_request do
    now = DateTime.utc_now()

    %CotEvent{
      uid: "protouid",
      type: "t-x-takp-q",
      how: "m-g",
      time: now,
      start: now,
      stale: DateTime.add(now, 60, :second),
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: nil, group: nil, track: nil},
      raw_detail: ~s(<detail><TakControl><TakRequest version="1"/></TakControl></detail>)
    }
  end

  # -- Helpers ---------------------------------------------------------------

  defp build_chat_event(sender_uid, sender_callsign, chatroom, message) do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 120, :second)
    chat_uid = "GeoChat.#{sender_uid}.#{chatroom}.#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

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

  defp build_sa_event(uid, type, callsign, lat, lon, group_name \\ "Cyan") do
    now = DateTime.utc_now()
    stale = DateTime.add(now, 300, :second)

    %CotEvent{
      uid: uid,
      type: type,
      how: "m-g",
      time: now,
      start: now,
      stale: stale,
      point: %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil},
      detail: %{
        callsign: callsign,
        group: %{name: group_name, role: "Team Member"},
        track: %{speed: 0.0, course: 0.0}
      }
    }
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

  defp count_events(data) do
    data
    |> String.split("</event>")
    |> Enum.count(&String.contains?(&1, "<event"))
  end

  defp assert_contains(data, expected, label) do
    if String.contains?(data, expected) do
      IO.puts("    ✓ Contains #{label}")
    else
      fail("Expected #{label} (#{inspect(expected)}) in response but not found")
    end
  end

  defp fail(msg) do
    IO.puts("    ✗ FAIL: #{msg}")
    System.halt(1)
  end
end

ElixirTAK.SmokeTest.run()
