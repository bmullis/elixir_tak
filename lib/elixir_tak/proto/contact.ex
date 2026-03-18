defmodule ElixirTAK.Proto.Contact do
  @moduledoc """
  Contact information (callsign and endpoint) for a TAK entity.

  Hand-written from `proto/contact.proto` in the ATAK-CIV repo.
  """
  use Protobuf, syntax: :proto3

  field(:endpoint, 1, type: :string)
  field(:callsign, 2, type: :string)
end
