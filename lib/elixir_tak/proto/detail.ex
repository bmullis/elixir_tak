defmodule ElixirTAK.Proto.Detail do
  @moduledoc """
  Protobuf detail sub-message containing structured fields and XML passthrough.

  Hand-written from `proto/detail.proto` in the ATAK-CIV repo.
  The `xml_detail` field carries any `<detail>` child elements that don't map
  to the structured sub-messages. Senders strip the outer `<detail>` wrapper;
  receivers re-wrap when converting back to XML.
  """
  use Protobuf, syntax: :proto3

  field(:xml_detail, 1, type: :string, json_name: "xmlDetail")
  field(:contact, 2, type: ElixirTAK.Proto.Contact)
  field(:group, 3, type: ElixirTAK.Proto.Group)

  field(:precision_location, 4,
    type: ElixirTAK.Proto.PrecisionLocation,
    json_name: "precisionLocation"
  )

  field(:status, 5, type: ElixirTAK.Proto.Status)
  field(:takv, 6, type: ElixirTAK.Proto.Takv)
  field(:track, 7, type: ElixirTAK.Proto.Track)
end
