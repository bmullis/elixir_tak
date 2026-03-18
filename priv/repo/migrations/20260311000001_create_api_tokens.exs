defmodule ElixirTAK.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :role, :string, null: false, default: "viewer"
      add :active, :boolean, null: false, default: true
      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:role])
    create index(:api_tokens, [:active])
  end
end
