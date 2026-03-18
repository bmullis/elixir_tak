defmodule ElixirTAK.Proto.Track do
  @moduledoc """
  Movement vector (speed and course) for a TAK entity.

  Hand-written from `proto/track.proto` in the ATAK-CIV repo.
  """
  use Protobuf, syntax: :proto3

  field(:speed, 1, type: :double)
  field(:course, 2, type: :double)
end
