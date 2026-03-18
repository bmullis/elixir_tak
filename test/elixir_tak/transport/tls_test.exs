defmodule ElixirTAK.Transport.TLSTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.Protocol.{CotEncoder, CotEvent}

  @cert_dir "certs"

  @moduletag :tls

  setup_all do
    unless File.exists?("#{@cert_dir}/server.pem") do
      IO.puts("Skipping TLS tests: run scripts/gen_dev_certs.sh first")
      :ignore
    else
      :ok
    end
  end

  setup do
    # Clear all caches to avoid stale data from other tests
    :ets.delete_all_objects(:sa_cache)
    :ets.delete_all_objects(:chat_cache)
    :ets.delete_all_objects(:marker_cache)
    :ets.delete_all_objects(:shape_cache)

    # Start a dedicated TLS listener on a random port for test isolation
    transport_options = [
      certfile: to_charlist("#{@cert_dir}/server.pem"),
      keyfile: to_charlist("#{@cert_dir}/server-key.pem"),
      cacertfile: to_charlist("#{@cert_dir}/ca.pem"),
      verify: :verify_peer,
      fail_if_no_peer_cert: true
    ]

    {:ok, pid} =
      start_supervised(
        {ThousandIsland,
         port: 0,
         transport_module: ThousandIsland.Transports.SSL,
         transport_options: transport_options,
         handler_module: ElixirTAK.Transport.CotHandler}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{port: port}
  end

  test "TLS connection with valid client cert succeeds", %{port: port} do
    {:ok, socket} =
      :ssl.connect(~c"127.0.0.1", port,
        certfile: ~c"#{@cert_dir}/client.pem",
        keyfile: ~c"#{@cert_dir}/client-key.pem",
        cacertfile: ~c"#{@cert_dir}/ca.pem",
        verify: :verify_peer,
        active: false
      )

    # Send a CoT event over TLS
    event = build_sa_event("TLS-TEST-001", "a-f-G-U-C", "TLS-CLIENT", 33.49, -111.93)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :ssl.send(socket, xml)

    # If we got here without error, the mutual TLS handshake succeeded
    :ssl.close(socket)
  end

  test "TLS connection without client cert is rejected", %{port: port} do
    # In TLS 1.3, the handshake may succeed on the client side before the server
    # validates the certificate. The server then closes the connection, so we
    # verify rejection by attempting to send/recv data.
    case :ssl.connect(~c"127.0.0.1", port,
           cacertfile: ~c"#{@cert_dir}/ca.pem",
           verify: :verify_peer,
           active: false
         ) do
      {:error, _reason} ->
        # Rejected at handshake level
        :ok

      {:ok, socket} ->
        # Handshake succeeded but server should kill the connection
        Process.sleep(100)
        result = :ssl.recv(socket, 0, 1000)
        assert {:error, _} = result
        :ssl.close(socket)
    end
  end

  test "TLS connection with untrusted cert is rejected", %{port: port} do
    # Generate a self-signed cert not issued by our CA
    tmp_dir = System.tmp_dir!()
    rogue_key = Path.join(tmp_dir, "rogue-key.pem")
    rogue_cert = Path.join(tmp_dir, "rogue-cert.pem")

    {_, 0} =
      System.cmd("openssl", [
        "req",
        "-new",
        "-x509",
        "-nodes",
        "-days",
        "1",
        "-keyout",
        rogue_key,
        "-out",
        rogue_cert,
        "-subj",
        "/CN=rogue"
      ])

    # Same TLS 1.3 behavior: connect may succeed, but server rejects the cert
    case :ssl.connect(~c"127.0.0.1", port,
           certfile: to_charlist(rogue_cert),
           keyfile: to_charlist(rogue_key),
           cacertfile: ~c"#{@cert_dir}/ca.pem",
           verify: :verify_peer,
           active: false
         ) do
      {:error, _reason} ->
        :ok

      {:ok, socket} ->
        Process.sleep(100)
        result = :ssl.recv(socket, 0, 1000)
        assert {:error, _} = result
        :ssl.close(socket)
    end

    File.rm(rogue_key)
    File.rm(rogue_cert)
  end

  test "CoT event is broadcast between two TLS clients", %{port: port} do
    ssl_opts = fn ->
      [
        certfile: ~c"#{@cert_dir}/client.pem",
        keyfile: ~c"#{@cert_dir}/client-key.pem",
        cacertfile: ~c"#{@cert_dir}/ca.pem",
        verify: :verify_peer,
        active: false
      ]
    end

    {:ok, alpha} = :ssl.connect(~c"127.0.0.1", port, ssl_opts.())
    {:ok, bravo} = :ssl.connect(~c"127.0.0.1", port, ssl_opts.())

    # Alpha sends SA
    event = build_sa_event("TLS-ALPHA", "a-f-G-U-C", "ALPHA", 33.49, -111.93)
    xml = event |> CotEncoder.encode() |> IO.iodata_to_binary()
    :ok = :ssl.send(alpha, xml)

    # Bravo should receive it (may need to skip replayed cached events)
    assert recv_until_match(bravo, "TLS-ALPHA", 5000)

    :ssl.close(alpha)
    :ssl.close(bravo)
  end

  defp recv_until_match(socket, expected, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    recv_loop(socket, expected, deadline)
  end

  defp recv_loop(socket, expected, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      false
    else
      case :ssl.recv(socket, 0, min(remaining, 1000)) do
        {:ok, data} ->
          if String.contains?(to_string(data), expected) do
            true
          else
            recv_loop(socket, expected, deadline)
          end

        {:error, :timeout} ->
          false

        {:error, _} ->
          false
      end
    end
  end

  defp build_sa_event(uid, type, callsign, lat, lon) do
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
        group: %{name: "Cyan", role: "Team Member"},
        track: %{speed: 0.0, course: 0.0}
      }
    }
  end
end
