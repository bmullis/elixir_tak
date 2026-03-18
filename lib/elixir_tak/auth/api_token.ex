defmodule ElixirTAK.Auth.ApiToken do
  @moduledoc "Ecto schema for API bearer tokens with role-based access."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "api_tokens" do
    field(:name, :string)
    field(:token_hash, :string)
    field(:role, :string, default: "viewer")
    field(:active, :boolean, default: true)
    field(:last_used_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @roles ~w(admin operator viewer)

  @doc "Valid roles for API tokens."
  def roles, do: @roles

  @doc "Build a changeset for creating or updating a token."
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :role, :active, :expires_at])
    |> validate_required([:name, :token_hash, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:token_hash)
  end

  @doc "Hash a raw token string for storage."
  def hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end

  @doc "Generate a random raw token (32 bytes, base62-ish)."
  def generate_raw_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc "Check if a token is expired."
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
