defmodule ElixirTAK.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_tak,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      ecto_repos: [ElixirTAK.Repo]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssl, :public_key],
      mod: {ElixirTAK.Application, []}
    ]
  end

  defp aliases do
    [
      smoke: "run scripts/smoke_test.exs",
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "dashboard.build": ["cmd --cd assets pnpm build"],
      "dashboard.install": ["cmd --cd assets pnpm install"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sweet_xml, "~> 0.7.0"},
      {:thousand_island, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:local_cluster, "~> 2.1", only: :test},
      {:ecto_sqlite3, "~> 0.17"},
      {:ecto, "~> 3.11"},
      {:protobuf, "~> 0.13"}
    ]
  end
end
