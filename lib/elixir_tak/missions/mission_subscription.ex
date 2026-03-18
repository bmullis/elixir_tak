defmodule ElixirTAK.Missions.MissionSubscription do
  @moduledoc "Ecto schema for mission subscriptions."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mission_subscriptions" do
    field(:client_uid, :string)

    belongs_to(:mission, ElixirTAK.Missions.Mission, type: :binary_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Build a changeset for a subscription."
  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:mission_id, :client_uid])
    |> validate_required([:mission_id, :client_uid])
    |> unique_constraint([:mission_id, :client_uid])
    |> foreign_key_constraint(:mission_id)
  end
end
