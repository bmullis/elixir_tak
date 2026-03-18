defmodule ElixirTAK.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :uid, :string, null: false
      add :type, :string, null: false
      add :how, :string
      add :callsign, :string
      add :group_name, :string
      add :lat, :float
      add :lon, :float
      add :hae, :float
      add :speed, :float
      add :course, :float
      add :raw_xml, :text
      add :event_time, :utc_datetime_usec, null: false
      add :stale_time, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:uid])
    create index(:events, [:type])
    create index(:events, [:event_time])
    create index(:events, [:group_name])
    create index(:events, [:lat, :lon])
  end
end
