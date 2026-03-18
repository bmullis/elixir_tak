defmodule ElixirTAK.Repo.Migrations.AddFederationFields do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :source_server, :string
    end

    create index(:events, [:source_server])
  end
end
