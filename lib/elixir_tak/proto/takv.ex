defmodule ElixirTAK.Proto.Takv do
  @moduledoc """
  TAK client version information (device, platform, OS, version).

  Hand-written from `proto/takv.proto` in the ATAK-CIV repo.
  """
  use Protobuf, syntax: :proto3

  field(:device, 1, type: :string)
  field(:platform, 2, type: :string)
  field(:os, 3, type: :string)
  field(:version, 4, type: :string)
end
