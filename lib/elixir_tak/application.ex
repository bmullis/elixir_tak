defmodule ElixirTAK.Application do
  @moduledoc """
  OTP Application for ElixirTAK.

  Starts the PubSub system, SA cache, plaintext TCP listener,
  and (optionally) a TLS listener for mutual-auth TAK clients.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    tcp_port = Application.get_env(:elixir_tak, :tcp_port, 8087)

    children =
      [
        {Phoenix.PubSub, name: ElixirTAK.PubSub},
        ElixirTAK.Repo,
        # Auto-migrate SQLite before caches that read from it
        {ElixirTAK.Release.Migrator, []},
        ElixirTAK.SACache,
        ElixirTAK.ChatCache,
        ElixirTAK.MarkerCache,
        ElixirTAK.ShapeCache,
        ElixirTAK.RouteCache,
        ElixirTAK.GeofenceCache,
        ElixirTAK.COP.Identity,
        ElixirTAK.VideoCache,
        ElixirTAK.VideoRegistry,
        {Registry, keys: :unique, name: ElixirTAK.Video.HLSRegistry},
        maybe_hls_supervisor(),
        ElixirTAK.DataPackages,
        ElixirTAK.CertStore,
        ElixirTAK.ClientRegistry,
        ElixirTAK.Metrics,
        ElixirTAK.Auth.TokenStore,
        ElixirTAK.Auth.AuditLog,
        ElixirTAK.Missions.MissionStore,
        ElixirTAK.History.Writer,
        ElixirTAK.History.Retention,
        ElixirTAKWeb.Endpoint,
        maybe_federation(),
        Supervisor.child_spec(
          {ThousandIsland, port: tcp_port, handler_module: ElixirTAK.Transport.CotHandler},
          id: :tak_tcp
        ),
        maybe_tls_listener(),
        maybe_simulator()
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: ElixirTAK.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_tls_listener do
    if Application.get_env(:elixir_tak, :tls_enabled, false) do
      tls_port = Application.get_env(:elixir_tak, :tls_port, 8089)
      certfile = Application.get_env(:elixir_tak, :certfile)
      keyfile = Application.get_env(:elixir_tak, :keyfile)
      cacertfile = Application.get_env(:elixir_tak, :cacertfile)
      verify_client = Application.get_env(:elixir_tak, :verify_client, true)

      if certfile && keyfile && cacertfile && File.exists?(certfile) do
        Logger.info("Starting TLS listener on port #{tls_port}")

        transport_options =
          [
            certfile: to_charlist(certfile),
            keyfile: to_charlist(keyfile),
            cacertfile: to_charlist(cacertfile)
          ] ++ client_verify_opts(verify_client)

        Supervisor.child_spec(
          {ThousandIsland,
           port: tls_port,
           transport_module: ThousandIsland.Transports.SSL,
           transport_options: transport_options,
           handler_module: ElixirTAK.Transport.CotHandler},
          id: :tak_tls
        )
      else
        Logger.info("TLS enabled but certs not found, skipping TLS listener")
        nil
      end
    end
  end

  defp maybe_federation do
    config = Application.get_env(:elixir_tak, ElixirTAK.Federation, [])

    if config[:enabled] do
      [
        # :pg scope must start before the federation transport
        %{id: ElixirTAK.PG, start: {:pg, :start_link, [ElixirTAK.PG]}},
        {ElixirTAK.Federation.Manager, []},
        {ElixirTAK.Federation.Transport.BEAM, manager: ElixirTAK.Federation.Manager}
      ]
    end
  end

  defp maybe_hls_supervisor do
    config = Application.get_env(:elixir_tak, ElixirTAK.Video.HLS, [])

    if config[:enabled] != false do
      {ElixirTAK.Video.HLSSupervisor, []}
    end
  end

  defp maybe_simulator do
    if Application.get_env(:elixir_tak, :simulator, false) do
      {ElixirTAK.Dev.Simulator, []}
    end
  end

  defp client_verify_opts(true) do
    cacertfile = Application.get_env(:elixir_tak, :cacertfile)

    # Load our CA cert for partial_chain matching
    ca_ders =
      if cacertfile && File.exists?(cacertfile) do
        cacertfile
        |> File.read!()
        |> :public_key.pem_decode()
        |> Enum.map(fn {:Certificate, der, _} -> der end)
      else
        []
      end

    [
      verify: :verify_peer,
      fail_if_no_peer_cert: true,
      # Erlang's SSL won't trust a self-signed CA by default --
      # partial_chain tells it our CA is a trusted root even though
      # it's not in the system trust store.
      partial_chain: fn chain ->
        if Enum.any?(chain, &(&1 in ca_ders)) do
          {:trusted_ca, List.last(chain)}
        else
          :unknown_ca
        end
      end
    ]
  end

  defp client_verify_opts(false) do
    [verify: :verify_none]
  end
end
