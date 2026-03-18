defmodule ElixirTAK.Proto.CotEvent do
  @moduledoc """
  Protobuf representation of a Cursor-on-Target event.

  Hand-written from `proto/cotevent.proto` in the ATAK-CIV repo.
  Maps nearly 1:1 to `ElixirTAK.Protocol.CotEvent`, with differences:
  - Timestamps are milliseconds since Unix epoch (not DateTime)
  - Sentinel value for unknown hae/ce/le is 9999999.0
  - Detail is a structured sub-message + xmlDetail passthrough
  """
  use Protobuf, syntax: :proto3

  field(:type, 1, type: :string)
  field(:access, 2, type: :string)
  field(:qos, 3, type: :string)
  field(:opex, 4, type: :string)
  field(:uid, 5, type: :string)
  field(:send_time, 6, type: :uint64, json_name: "sendTime")
  field(:start_time, 7, type: :uint64, json_name: "startTime")
  field(:stale_time, 8, type: :uint64, json_name: "staleTime")
  field(:how, 9, type: :string)
  field(:lat, 10, type: :double)
  field(:lon, 11, type: :double)
  field(:hae, 12, type: :double)
  field(:ce, 13, type: :double)
  field(:le, 14, type: :double)
  field(:detail, 15, type: ElixirTAK.Proto.Detail)
end
