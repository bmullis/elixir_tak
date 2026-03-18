defmodule ElixirTAK.Proto.PrecisionLocation do
  @moduledoc """
  Precision location source metadata.

  Hand-written from `proto/precisionlocation.proto` in the ATAK-CIV repo.
  """
  use Protobuf, syntax: :proto3

  field(:geopointsrc, 1, type: :string)
  field(:altsrc, 2, type: :string)
end
