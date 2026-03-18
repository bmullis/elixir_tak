defmodule ElixirTAK.Auth.TokenStore do
  @moduledoc """
  ETS-backed token store for fast API auth lookups.

  Loads tokens from SQLite on startup and keeps them cached in ETS.
  Mutations go to both ETS and SQLite.
  """

  use GenServer

  alias ElixirTAK.Auth.ApiToken
  alias ElixirTAK.Repo

  import Ecto.Query

  @table :api_tokens

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Create a new API token. Returns `{:ok, raw_token, record}` or `{:error, changeset}`."
  def create(name, role, opts \\ []) do
    raw_token = ApiToken.generate_raw_token()
    token_hash = ApiToken.hash_token(raw_token)

    attrs = %{
      name: name,
      token_hash: token_hash,
      role: role,
      expires_at: Keyword.get(opts, :expires_at)
    }

    case %ApiToken{} |> ApiToken.changeset(attrs) |> Repo.insert() do
      {:ok, record} ->
        :ets.insert(@table, {token_hash, record})
        {:ok, raw_token, record}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Look up a token by its raw bearer value. Returns `{:ok, record}` or `:not_found`."
  def lookup(raw_token) do
    token_hash = ApiToken.hash_token(raw_token)

    case :ets.lookup(@table, token_hash) do
      [{^token_hash, record}] ->
        cond do
          not record.active -> :not_found
          ApiToken.expired?(record) -> :not_found
          true -> {:ok, record}
        end

      [] ->
        :not_found
    end
  end

  @doc "Record that a token was just used (async, non-blocking)."
  def touch(token_hash) do
    # Skip async DB update in test to avoid sandbox connection conflicts
    if Application.get_env(:elixir_tak, :env) != :test do
      GenServer.cast(__MODULE__, {:touch, token_hash})
    end
  end

  @doc "Revoke (deactivate) a token by ID."
  def revoke(token_id) do
    case Repo.get(ApiToken, token_id) do
      nil ->
        :not_found

      record ->
        {:ok, updated} =
          record
          |> Ecto.Changeset.change(%{active: false})
          |> Repo.update()

        :ets.insert(@table, {updated.token_hash, updated})
        :ok
    end
  end

  @doc "Delete a token permanently by ID."
  def delete(token_id) do
    case Repo.get(ApiToken, token_id) do
      nil ->
        :not_found

      record ->
        Repo.delete(record)
        :ets.delete(@table, record.token_hash)
        :ok
    end
  end

  @doc "List all tokens (without exposing raw token values)."
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_hash, record} -> record end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc "Get count of active tokens."
  def count do
    :ets.info(@table, :size)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    load_from_db()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:touch, token_hash}, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    case :ets.lookup(@table, token_hash) do
      [{^token_hash, record}] ->
        updated = %{record | last_used_at: now}
        :ets.insert(@table, {token_hash, updated})

        try do
          from(t in ApiToken, where: t.token_hash == ^token_hash)
          |> Repo.update_all(set: [last_used_at: now])
        rescue
          _ -> :ok
        end

      [] ->
        :ok
    end

    {:noreply, state}
  end

  defp load_from_db do
    Repo.all(ApiToken)
    |> Enum.each(fn record ->
      :ets.insert(@table, {record.token_hash, record})
    end)
  end
end
