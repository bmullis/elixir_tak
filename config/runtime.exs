import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :elixir_tak, ElixirTAKWeb.Endpoint, secret_key_base: secret_key_base

  config :elixir_tak,
    tcp_port: String.to_integer(System.get_env("TAK_TCP_PORT") || "8087"),
    tls_port: String.to_integer(System.get_env("TAK_TLS_PORT") || "8089"),
    tls_enabled: System.get_env("TAK_TLS_ENABLED", "true") == "true",
    certfile: System.get_env("TAK_CERTFILE", "certs/server.pem"),
    keyfile: System.get_env("TAK_KEYFILE", "certs/server-key.pem"),
    cacertfile: System.get_env("TAK_CACERTFILE", "certs/ca.pem"),
    verify_client: System.get_env("TAK_VERIFY_CLIENT", "true") == "true"

  config :elixir_tak, ElixirTAK.Repo,
    database: System.get_env("TAK_DATABASE", "data/elixir_tak.db")

  certfile = Path.expand(System.get_env("TAK_CERTFILE", "certs/server.pem"))
  keyfile = Path.expand(System.get_env("TAK_KEYFILE", "certs/server-key.pem"))
  cacertfile = Path.expand(System.get_env("TAK_CACERTFILE", "certs/ca.pem"))

  endpoint_config = [
    http: [port: String.to_integer(System.get_env("TAK_HTTP_PORT") || "8080")],
    server: true
  ]

  endpoint_config =
    if File.exists?(certfile) and File.exists?(keyfile) do
      Keyword.put(endpoint_config, :https,
        port: String.to_integer(System.get_env("TAK_HTTPS_PORT") || "8443"),
        cipher_suite: :strong,
        certfile: certfile,
        keyfile: keyfile,
        cacertfile: cacertfile,
        verify: :verify_peer,
        fail_if_no_peer_cert: false
      )
    else
      endpoint_config
    end

  config :elixir_tak, ElixirTAKWeb.Endpoint, endpoint_config

  # Federation
  federation_enabled = System.get_env("FEDERATION_ENABLED", "false") == "true"

  federation_transport =
    case System.get_env("FEDERATION_TRANSPORT", "beam") do
      "beam" -> :beam
      "nats" -> :nats
      _ -> :beam
    end

  federation_peers =
    case System.get_env("FEDERATION_PEERS") do
      nil -> []
      "" -> []
      peers -> peers |> String.split(",") |> Enum.map(&String.to_atom/1)
    end

  config :elixir_tak, ElixirTAK.Federation,
    enabled: federation_enabled,
    transport: federation_transport,
    server_name: System.get_env("FEDERATION_SERVER_NAME", "ElixirTAK"),
    peers: federation_peers

  # Video HLS transcoding
  config :elixir_tak, ElixirTAK.Video.HLS,
    enabled: System.get_env("TAK_HLS_ENABLED", "true") == "true",
    ffmpeg_bin: System.get_env("TAK_FFMPEG_BIN", "ffmpeg"),
    hls_dir: System.get_env("TAK_HLS_DIR", "data/hls"),
    snapshot_dir: System.get_env("TAK_SNAPSHOT_DIR", "data/snapshots")
end
