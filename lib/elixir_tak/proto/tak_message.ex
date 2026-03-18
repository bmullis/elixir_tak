defmodule ElixirTAK.Proto.TakMessage do
  @moduledoc """
  Top-level TAK protocol message wrapper.

  Hand-written from `proto/takmessage.proto` in the ATAK-CIV repo.
  Wraps either a TakControl (for protocol negotiation) or a CotEvent (for data).
  """
  use Protobuf, syntax: :proto3

  field(:tak_control, 1, type: ElixirTAK.Proto.TakControl, json_name: "takControl")
  field(:cot_event, 2, type: ElixirTAK.Proto.CotEvent, json_name: "cotEvent")
end
