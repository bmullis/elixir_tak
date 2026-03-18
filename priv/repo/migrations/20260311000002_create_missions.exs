defmodule ElixirTAK.Repo.Migrations.CreateMissions do
  use Ecto.Migration

  def change do
    create table(:missions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :creator_uid, :string
      add :group_name, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:missions, [:name])

    create table(:mission_contents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
      add :content_type, :string, null: false
      add :content_uid, :string, null: false
      add :data_package_hash, :string
      add :metadata, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:mission_contents, [:mission_id])
    create unique_index(:mission_contents, [:mission_id, :content_type, :content_uid])

    create table(:mission_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
      add :client_uid, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:mission_subscriptions, [:mission_id])
    create unique_index(:mission_subscriptions, [:mission_id, :client_uid])

    create table(:audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :actor, :string
      add :role, :string
      add :resource_type, :string
      add :resource_id, :string
      add :details, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_log, [:action])
    create index(:audit_log, [:actor])
    create index(:audit_log, [:inserted_at])
  end
end
