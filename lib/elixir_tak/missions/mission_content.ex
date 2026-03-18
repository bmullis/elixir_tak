defmodule ElixirTAK.Missions.MissionContent do
  @moduledoc "Ecto schema for mission contents (data packages, markers, etc.)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mission_contents" do
    field(:content_type, :string)
    field(:content_uid, :string)
    field(:data_package_hash, :string)
    field(:metadata, :string)

    belongs_to(:mission, ElixirTAK.Missions.Mission, type: :binary_id)

    timestamps(type: :utc_datetime_usec)
  end

  @content_types ~w(data_package marker route shape)

  @doc "Build a changeset for mission content."
  def changeset(content, attrs) do
    content
    |> cast(attrs, [:mission_id, :content_type, :content_uid, :data_package_hash, :metadata])
    |> validate_required([:mission_id, :content_type, :content_uid])
    |> validate_inclusion(:content_type, @content_types)
    |> unique_constraint([:mission_id, :content_type, :content_uid])
    |> foreign_key_constraint(:mission_id)
  end
end
