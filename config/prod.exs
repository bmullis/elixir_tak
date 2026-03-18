import Config

config :elixir_tak,
  simulator: false

config :elixir_tak, ElixirTAKWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info
