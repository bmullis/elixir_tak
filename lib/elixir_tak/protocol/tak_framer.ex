defmodule ElixirTAK.Protocol.TakFramer do
  @moduledoc """
  Stateful framer that handles the TAK protocol wire format.

  Detects whether the byte stream uses raw XML CoT (legacy) or the TAK protobuf
  framing (`0xBF <varint length> <protobuf payload>`), then delegates accordingly.

  In XML mode, delegates to `CotFramer` for event boundary detection.
  In protobuf mode, extracts length-prefixed protobuf messages directly.

  Mode detection happens on the first byte received:
  - `0xBF` (191) -> protobuf stream mode
  - Anything else -> raw XML mode

  Once detected, the mode is fixed for the lifetime of the connection.
  The handler can also force a mode switch after protocol negotiation.
  """

  import Bitwise

  alias ElixirTAK.Protocol.{CotFramer, ProtoParser}

  @max_buffer_size 1_048_576

  defstruct mode: :detect,
            xml_framer: nil,
            buffer: <<>>

  @type mode :: :detect | :xml | :protobuf
  @type t :: %__MODULE__{
          mode: mode(),
          xml_framer: CotFramer.t() | nil,
          buffer: binary()
        }

  @doc "Returns a new framer in auto-detect mode."
  @spec new() :: t()
  def new, do: %__MODULE__{xml_framer: CotFramer.new()}

  @doc """
  Force the framer into protobuf mode.

  Called after successful protocol negotiation when the connection
  switches from XML to protobuf mid-stream.
  """
  @spec switch_to_protobuf(t()) :: t()
  def switch_to_protobuf(%__MODULE__{} = framer) do
    %{framer | mode: :protobuf, xml_framer: nil, buffer: <<>>}
  end

  @doc """
  Push bytes into the framer and extract complete events.

  Returns `{events, new_framer}` where each event is one of:
  - `{:ok, %CotEvent{}, raw_binary}` - successfully parsed event
  - `{:error, reason}` - parse/decode failure

  In XML mode, `raw_binary` is the XML string.
  In protobuf mode, `raw_binary` is the protobuf payload (without the 0xBF/varint header).
  """
  @spec push(t(), binary()) :: {[term()], t()}
  def push(%__MODULE__{mode: :detect} = framer, bytes) do
    buffer = framer.buffer <> bytes

    case detect_mode(buffer) do
      {:xml, rest} ->
        push(%{framer | mode: :xml, buffer: <<>>}, rest)

      {:protobuf, rest} ->
        push(%{framer | mode: :protobuf, xml_framer: nil, buffer: <<>>}, rest)

      :need_more ->
        {[], %{framer | buffer: buffer}}
    end
  end

  def push(%__MODULE__{mode: :xml} = framer, bytes) do
    case CotFramer.push(framer.xml_framer, bytes) do
      {:error, :buffer_overflow, new_xml_framer} ->
        {[{:error, :buffer_overflow}], %{framer | xml_framer: new_xml_framer}}

      {xml_events, new_xml_framer} ->
        events = Enum.map(xml_events, fn xml -> {:xml, xml} end)
        {events, %{framer | xml_framer: new_xml_framer}}
    end
  end

  def push(%__MODULE__{mode: :protobuf} = framer, bytes) do
    buffer = framer.buffer <> bytes

    if byte_size(buffer) > @max_buffer_size do
      {[{:error, :buffer_overflow}], %{framer | buffer: <<>>}}
    else
      extract_protobuf_messages(buffer, framer, [])
    end
  end

  @doc "Returns the current framing mode."
  @spec mode(t()) :: mode()
  def mode(%__MODULE__{mode: m}), do: m

  # -- Mode detection ----------------------------------------------------------

  defp detect_mode(<<0xBF, _rest::binary>> = buffer), do: {:protobuf, buffer}
  defp detect_mode(<<_byte, _rest::binary>> = buffer), do: {:xml, buffer}
  defp detect_mode(<<>>), do: :need_more

  # -- Protobuf message extraction --------------------------------------------

  defp extract_protobuf_messages(<<0xBF, rest::binary>>, framer, events) do
    case decode_varint(rest) do
      {:ok, length, payload_start} when byte_size(payload_start) >= length ->
        <<payload::binary-size(length), remaining::binary>> = payload_start

        event =
          case ProtoParser.parse(payload) do
            {:ok, cot_event} -> {:ok, cot_event, payload}
            error -> error
          end

        extract_protobuf_messages(remaining, framer, [event | events])

      {:ok, _length, _payload_start} ->
        # Incomplete message, buffer for next push
        {Enum.reverse(events), %{framer | buffer: <<0xBF, rest::binary>>}}

      :incomplete ->
        {Enum.reverse(events), %{framer | buffer: <<0xBF, rest::binary>>}}
    end
  end

  defp extract_protobuf_messages(<<>>, framer, events) do
    {Enum.reverse(events), %{framer | buffer: <<>>}}
  end

  defp extract_protobuf_messages(<<_byte, rest::binary>>, framer, events) do
    # Non-0xBF byte in protobuf mode: skip (shouldn't happen in normal operation)
    extract_protobuf_messages(rest, framer, events)
  end

  # -- Varint decoding ---------------------------------------------------------

  @doc """
  Decode a protobuf-style varint from the beginning of a binary.

  Returns `{:ok, value, rest}` or `:incomplete`.
  """
  @spec decode_varint(binary()) :: {:ok, non_neg_integer(), binary()} | :incomplete
  def decode_varint(binary), do: do_decode_varint(binary, 0, 0)

  defp do_decode_varint(<<>>, _acc, _shift), do: :incomplete

  defp do_decode_varint(<<1::1, value::7, rest::binary>>, acc, shift) do
    do_decode_varint(rest, acc ||| value <<< shift, shift + 7)
  end

  defp do_decode_varint(<<0::1, value::7, rest::binary>>, acc, shift) do
    {:ok, acc ||| value <<< shift, rest}
  end

  # -- Varint encoding ---------------------------------------------------------

  @doc """
  Encode an integer as a protobuf-style varint binary.
  """
  @spec encode_varint(non_neg_integer()) :: binary()
  def encode_varint(value) when value < 128, do: <<value::8>>

  def encode_varint(value) do
    <<1::1, value::7, encode_varint(value >>> 7)::binary>>
  end

  @doc """
  Wrap a protobuf payload binary in TAK stream framing.

  Prepends the magic byte `0xBF` and a varint-encoded payload length.
  """
  @spec frame_protobuf(binary()) :: binary()
  def frame_protobuf(payload) when is_binary(payload) do
    <<0xBF, encode_varint(byte_size(payload))::binary, payload::binary>>
  end
end
