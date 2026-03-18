defmodule ElixirTAK.Release do
  @moduledoc "Release tasks for database migrations."

  @app :elixir_tak

  @doc "Run all pending Ecto migrations."
  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rollback the last migration."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp load_app do
    Application.ensure_all_started(:ecto_sqlite3)
  end
end

defmodule ElixirTAK.Release.Migrator do
  @moduledoc """
  Runs Ecto migrations synchronously on startup.

  Placed in the supervision tree after the Repo but before any
  processes that read from the database (TokenStore, etc.).
  Uses a GenServer that migrates in init/1 so the supervisor
  blocks until migrations complete before starting the next child.
  """

  use GenServer, restart: :transient

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    migrate()
    :ignore
  end

  defp migrate do
    migrations_path = Application.app_dir(:elixir_tak, "priv/repo/migrations")

    migrated = Ecto.Migrator.run(ElixirTAK.Repo, migrations_path, :up, all: true)

    if migrated != [] do
      Logger.info("Ran #{length(migrated)} migration(s)")
    end
  rescue
    e ->
      Logger.warning("Auto-migration failed: #{Exception.message(e)}")
  end
end
