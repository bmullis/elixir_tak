defmodule ElixirTAK.Proto.TakControl do
  @moduledoc """
  TAK protocol version negotiation control message.

  Hand-written from `proto/takcontrol.proto` in the ATAK-CIV repo.
  Used during the initial handshake to agree on protobuf version.
  """
  use Protobuf, syntax: :proto3

  field(:min_proto_version, 1, type: :uint32, json_name: "minProtoVersion")
  field(:max_proto_version, 2, type: :uint32, json_name: "maxProtoVersion")
  field(:contact_uid, 3, type: :string, json_name: "contactUid")
end
