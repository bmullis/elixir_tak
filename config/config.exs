import Config

config :phoenix, :json_library, Jason

# Allow Phoenix :accepts plug to recognize "xml" format
config :mime, :types, %{
  "application/xml" => ["xml"]
}

config :elixir_tak, ecto_repos: [ElixirTAK.Repo]

config :elixir_tak, ElixirTAK.Repo,
  database: "data/elixir_tak.db",
  journal_mode: :wal,
  pool_size: 5

config :elixir_tak, ElixirTAK.History.Retention,
  max_age_hours: 168,
  cleanup_interval_minutes: 60

config :elixir_tak,
  dashboard_callsign: "ElixirTAK-COP",
  dashboard_group: "Cyan"

config :elixir_tak, ElixirTAK.Federation,
  enabled: false,
  transport: :beam,
  server_name: "ElixirTAK",
  peers: []

config :elixir_tak, ElixirTAK.Video.HLS,
  enabled: true,
  ffmpeg_bin: "ffmpeg",
  hls_dir: "data/hls",
  snapshot_dir: "data/snapshots",
  hls_time: 2,
  hls_list_size: 5

config :elixir_tak, ElixirTAKWeb.Endpoint,
  url: [host: "localhost"],
  server: true,
  pubsub_server: ElixirTAK.PubSub,
  secret_key_base:
    "tak-dev-secret-key-base-must-be-at-least-64-bytes-long-for-cookie-session-signing"

import_config "#{config_env()}.exs"
