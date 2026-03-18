defmodule ElixirTAK.Proto.Status do
  @moduledoc """
  Device status (battery level) for a TAK entity.

  Hand-written from `proto/status.proto` in the ATAK-CIV repo.
  """
  use Protobuf, syntax: :proto3

  field(:battery, 1, type: :uint32)
end
