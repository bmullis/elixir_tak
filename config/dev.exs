import Config

config :elixir_tak,
  tcp_port: 8087,
  tls_port: 8089,
  tls_enabled: true,
  certfile: "certs/server.pem",
  keyfile: "certs/server-key.pem",
  cacertfile: "certs/ca.pem",
  verify_client: true,
  simulator: true

config :elixir_tak, ElixirTAKWeb.Endpoint,
  http: [port: 8080],
  https: [
    port: 8443,
    cipher_suite: :strong,
    certfile: Path.expand("../certs/server.pem", __DIR__),
    keyfile: Path.expand("../certs/server-key.pem", __DIR__),
    cacertfile: Path.expand("../certs/ca.pem", __DIR__),
    verify: :verify_peer,
    fail_if_no_peer_cert: false
  ],
  debug_errors: true,
  check_origin: false,
  watchers: [
    pnpm: [
      "vite", "build", "--watch",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# Federation (uncomment to enable for multi-node dev testing)
# config :elixir_tak, ElixirTAK.Federation,
#   enabled: true,
#   transport: :beam,
#   server_name: "ElixirTAK-Dev",
#   peers: [:"tak2@hostname"]
