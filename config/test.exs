import Config

config :elixir_tak, ElixirTAK.Repo,
  database: "data/elixir_tak_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

config :elixir_tak, ElixirTAK.History.Retention,
  max_age_hours: 1,
  cleanup_interval_minutes: 999_999

config :elixir_tak,
  env: :test,
  tcp_port: 18087,
  tls_port: 18089,
  tls_enabled: false,
  certfile: "certs/server.pem",
  keyfile: "certs/server-key.pem",
  cacertfile: "certs/ca.pem",
  verify_client: true,
  simulator: false

config :elixir_tak, ElixirTAKWeb.Endpoint,
  http: [port: 4002],
  server: false
