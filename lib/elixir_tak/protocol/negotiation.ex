defmodule ElixirTAK.Protocol.Negotiation do
  @moduledoc """
  TAK protocol version negotiation.

  When a client connects over TCP/TLS, the server sends a version offer
  (`t-x-takp-v`) advertising protobuf support. If the client supports protobuf,
  it responds with a version request (`t-x-takp-q`). The server confirms with
  a version response (`t-x-takp-r`), and both sides switch to protobuf framing.

  Clients that don't understand the offer simply ignore it and continue with XML.
  """

  alias ElixirTAK.Protocol.CotEvent

  @supported_version 1

  @doc "Build the server's protocol version offer event (t-x-takp-v)."
  @spec version_offer() :: CotEvent.t()
  def version_offer do
    now = DateTime.utc_now()

    %CotEvent{
      uid: "protouid",
      type: "t-x-takp-v",
      how: "m-g",
      time: now,
      start: now,
      stale: DateTime.add(now, 60, :second),
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: nil, group: nil, track: nil},
      raw_detail:
        "<detail><TakControl><TakProtocolSupport version=\"#{@supported_version}\"/></TakControl></detail>"
    }
  end

  @doc "Check if an event is a protocol negotiation event (any t-x-takp-* type)."
  @spec negotiation_event?(CotEvent.t()) :: boolean()
  def negotiation_event?(%CotEvent{type: "t-x-takp-" <> _}), do: true
  def negotiation_event?(_), do: false

  @doc "Check if an event is a protocol negotiation request (t-x-takp-q)."
  @spec negotiation_request?(CotEvent.t()) :: boolean()
  def negotiation_request?(%CotEvent{type: "t-x-takp-q"}), do: true
  def negotiation_request?(_), do: false

  @doc "Extract the requested protocol version from a negotiation request."
  @spec requested_version(CotEvent.t()) :: non_neg_integer() | nil
  def requested_version(%CotEvent{raw_detail: raw}) when is_binary(raw) do
    case Regex.run(~r/version="(\d+)"/, raw) do
      [_, v] -> String.to_integer(v)
      nil -> nil
    end
  end

  def requested_version(_), do: nil

  @doc "Check if the server supports the requested protocol version."
  @spec supported_version?(non_neg_integer()) :: boolean()
  def supported_version?(version), do: version == @supported_version

  @doc "Build the server's protocol negotiation response (t-x-takp-r)."
  @spec version_response(boolean()) :: CotEvent.t()
  def version_response(accepted) do
    now = DateTime.utc_now()
    status = if accepted, do: "true", else: "false"

    %CotEvent{
      uid: "protouid",
      type: "t-x-takp-r",
      how: "m-g",
      time: now,
      start: now,
      stale: DateTime.add(now, 60, :second),
      point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil},
      detail: %{callsign: nil, group: nil, track: nil},
      raw_detail: "<detail><TakControl><TakResponse status=\"#{status}\"/></TakControl></detail>"
    }
  end
end
