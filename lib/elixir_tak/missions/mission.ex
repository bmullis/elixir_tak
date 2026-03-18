defmodule ElixirTAK.Missions.Mission do
  @moduledoc "Ecto schema for missions."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "missions" do
    field(:name, :string)
    field(:description, :string)
    field(:creator_uid, :string)
    field(:group_name, :string)

    has_many(:contents, ElixirTAK.Missions.MissionContent)
    has_many(:subscriptions, ElixirTAK.Missions.MissionSubscription)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Build a changeset for a mission."
  def changeset(mission, attrs) do
    mission
    |> cast(attrs, [:name, :description, :creator_uid, :group_name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:name)
  end
end
