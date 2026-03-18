defmodule ElixirTAK.Proto.Group do
  @moduledoc """
  Team/group membership for a TAK entity.

  Hand-written from `proto/group.proto` in the ATAK-CIV repo.
  """
  use Protobuf, syntax: :proto3

  field(:name, 1, type: :string)
  field(:role, 2, type: :string)
end
