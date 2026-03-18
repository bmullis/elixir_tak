defmodule ElixirTAK.Protocol.CotFramer do
  @moduledoc """
  Stateful byte buffer that extracts complete `<event>...</event>` XML documents
  from a raw TCP byte stream.

  Tracks XML depth by counting `<event` opens and `</event>` closes.
  Self-closing tags (`<point/>`, `<contact/>`) and other non-event tags are
  skipped without affecting depth.

  This module is pure protocol logic with no networking dependency.
  """

  @max_buffer_size 1_048_576

  defstruct buffer: <<>>,
            scan_pos: 0,
            event_start: nil,
            depth: 0

  @type t :: %__MODULE__{
          buffer: binary(),
          scan_pos: non_neg_integer(),
          event_start: non_neg_integer() | nil,
          depth: non_neg_integer()
        }

  @doc "Returns a new empty framer state."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Appends bytes to the buffer and extracts all complete events.

  Returns `{events, new_framer}` where `events` is a list of complete XML binaries.
  Returns `{:error, :buffer_overflow, new_framer}` if the buffer exceeds 1MB.
  """
  @spec push(t(), binary()) ::
          {[binary()], t()} | {:error, :buffer_overflow, t()}
  def push(%__MODULE__{} = framer, bytes) when is_binary(bytes) do
    new_buffer = framer.buffer <> bytes

    if byte_size(new_buffer) > @max_buffer_size do
      {:error, :buffer_overflow, new()}
    else
      scan(%{framer | buffer: new_buffer}, [])
    end
  end

  # -------------------------------------------------------------------
  # Core scan loop
  #
  # We advance `scan_pos` through the buffer looking for `<` characters.
  # When we find one we classify the tag and either:
  #   - record an event_start and set depth to 1  (opening <event)
  #   - increment depth                           (nested <event, unlikely but safe)
  #   - decrement depth, emit if depth → 0        (</event>)
  #   - ignore                                    (any other tag)
  # -------------------------------------------------------------------

  defp scan(%__MODULE__{buffer: buffer, scan_pos: pos} = f, events) do
    case find_lt(buffer, pos) do
      :not_found ->
        finish(f, events)

      lt_pos ->
        case classify(buffer, lt_pos) do
          {:event_open, after_pos} ->
            handle_event_open(f, lt_pos, after_pos, events)

          {:event_self_close, after_pos} ->
            handle_event_self_close(f, lt_pos, after_pos, events)

          {:event_close, after_pos} ->
            handle_event_close(f, after_pos, events)

          {:other, after_pos} ->
            scan(%{f | scan_pos: after_pos}, events)

          :incomplete ->
            finish_incomplete(f, lt_pos, events)
        end
    end
  end

  # -- Handlers for each tag kind -------------------------------------------

  defp handle_event_open(f, lt_pos, after_pos, events) do
    if f.depth == 0 do
      # Starting a new event
      scan(%{f | scan_pos: after_pos, event_start: lt_pos, depth: 1}, events)
    else
      # Nested <event (unusual but be safe)
      scan(%{f | scan_pos: after_pos, depth: f.depth + 1}, events)
    end
  end

  defp handle_event_self_close(f, lt_pos, after_pos, events) do
    if f.depth == 0 do
      # A complete self-closing <event ... /> at top level
      event_xml = binary_part(f.buffer, lt_pos, after_pos - lt_pos)
      # Compact: drop everything up to after_pos
      remaining = binary_part(f.buffer, after_pos, byte_size(f.buffer) - after_pos)

      scan(%{f | buffer: remaining, scan_pos: 0, event_start: nil, depth: 0}, [event_xml | events])
    else
      # Self-closing <event inside another event — just a weird nested tag, skip
      scan(%{f | scan_pos: after_pos}, events)
    end
  end

  defp handle_event_close(f, after_pos, events) do
    cond do
      f.depth <= 0 ->
        # Stray </event> outside any event — skip
        scan(%{f | scan_pos: after_pos}, events)

      f.depth == 1 ->
        # Closing the outermost event — emit!
        event_xml = binary_part(f.buffer, f.event_start, after_pos - f.event_start)
        remaining = binary_part(f.buffer, after_pos, byte_size(f.buffer) - after_pos)

        scan(%{f | buffer: remaining, scan_pos: 0, event_start: nil, depth: 0}, [
          event_xml | events
        ])

      true ->
        # Closing a nested event
        scan(%{f | scan_pos: after_pos, depth: f.depth - 1}, events)
    end
  end

  # -- Finish: return accumulated events and compact buffer -----------------

  # Called when no more `<` found in buffer
  defp finish(f, events) do
    framer =
      if f.depth == 0 and f.event_start == nil do
        # Not inside an event — discard everything except a possible
        # trailing partial "<event" prefix
        kept = keep_trailing_prefix(f.buffer, f.scan_pos)
        %{f | buffer: kept, scan_pos: 0}
      else
        f
      end

    {Enum.reverse(events), framer}
  end

  # Called when a `<` was found but the tag is incomplete (split across pushes)
  defp finish_incomplete(f, lt_pos, events) do
    framer =
      if f.depth == 0 and f.event_start == nil do
        # Keep from the incomplete tag's `<` onward
        kept = binary_part(f.buffer, lt_pos, byte_size(f.buffer) - lt_pos)
        %{f | buffer: kept, scan_pos: 0}
      else
        # Inside an event — keep buffer as-is, but park scan at the
        # incomplete tag so we retry it after more bytes arrive
        %{f | scan_pos: lt_pos}
      end

    {Enum.reverse(events), framer}
  end

  # -- Find the next `<` at or after `pos` ----------------------------------

  defp find_lt(buffer, pos) when pos >= byte_size(buffer), do: :not_found

  defp find_lt(buffer, pos) do
    rest = binary_part(buffer, pos, byte_size(buffer) - pos)

    case :binary.match(rest, "<") do
      :nomatch -> :not_found
      {offset, 1} -> pos + offset
    end
  end

  # -- Classify the tag starting at `lt_pos` --------------------------------
  #
  # Returns one of:
  #   {:event_open, after_pos}        — <event ...>
  #   {:event_self_close, after_pos}  — <event .../>
  #   {:event_close, after_pos}       — </event>
  #   {:other, after_pos}             — any other tag
  #   :incomplete                     — tag not yet complete in buffer
  #

  defp classify(buffer, lt_pos) do
    remaining = byte_size(buffer) - lt_pos

    cond do
      remaining < 2 ->
        :incomplete

      # Closing tag: </
      binary_part(buffer, lt_pos + 1, 1) == "/" ->
        classify_close_tag(buffer, lt_pos)

      true ->
        classify_open_tag(buffer, lt_pos)
    end
  end

  defp classify_close_tag(buffer, lt_pos) do
    after_slash = lt_pos + 2
    rest = binary_part(buffer, after_slash, byte_size(buffer) - after_slash)

    case :binary.match(rest, ">") do
      :nomatch ->
        :incomplete

      {offset, 1} ->
        tag_name =
          binary_part(rest, 0, offset)
          |> String.trim()

        after_pos = after_slash + offset + 1

        if tag_name == "event" do
          {:event_close, after_pos}
        else
          {:other, after_pos}
        end
    end
  end

  defp classify_open_tag(buffer, lt_pos) do
    # We need to find the end of this tag: either > or />
    # We must respect quoted attribute values that might contain > or />
    after_lt = lt_pos + 1
    rest = binary_part(buffer, after_lt, byte_size(buffer) - after_lt)

    case find_tag_end(rest, 0) do
      :incomplete ->
        :incomplete

      {:normal, rel_end} ->
        # Tag ends with >, tag content is rest[0..rel_end-1]
        tag_content = binary_part(rest, 0, rel_end)
        tag_name = extract_tag_name(tag_content)
        after_pos = after_lt + rel_end + 1

        if tag_name == "event" do
          {:event_open, after_pos}
        else
          {:other, after_pos}
        end

      {:self_closing, rel_end} ->
        # Tag ends with />, tag content is rest[0..rel_end-1]
        tag_content = binary_part(rest, 0, rel_end)
        tag_name = extract_tag_name(tag_content)
        after_pos = after_lt + rel_end + 2

        if tag_name == "event" do
          {:event_self_close, after_pos}
        else
          {:other, after_pos}
        end
    end
  end

  # -- Find the end of a tag's content (respecting quoted attrs) ------------
  #
  # Scans forward from the first char after `<`.
  # Returns {:normal, pos} for `>` and {:self_closing, pos} for `/>`.
  # `pos` is the offset of the `>` or `/` within the given binary.

  defp find_tag_end(<<>>, _pos), do: :incomplete
  defp find_tag_end(<<?", rest::binary>>, pos), do: skip_quote(rest, ?", pos + 1)
  defp find_tag_end(<<?', rest::binary>>, pos), do: skip_quote(rest, ?', pos + 1)
  defp find_tag_end(<<"/>", _::binary>>, pos), do: {:self_closing, pos}
  defp find_tag_end(<<?>, _::binary>>, pos), do: {:normal, pos}
  defp find_tag_end(<<_, rest::binary>>, pos), do: find_tag_end(rest, pos + 1)

  defp skip_quote(<<>>, _q, _pos), do: :incomplete
  defp skip_quote(<<c, rest::binary>>, q, pos) when c == q, do: find_tag_end(rest, pos + 1)
  defp skip_quote(<<_, rest::binary>>, q, pos), do: skip_quote(rest, q, pos + 1)

  # -- Extract the tag name from content after `<` -------------------------

  defp extract_tag_name(content) do
    # Tag name is everything up to the first whitespace, /, or >
    # Handle __group and other names with underscores
    case :binary.match(content, [" ", "\t", "\n", "\r"]) do
      :nomatch -> content
      {pos, _} -> binary_part(content, 0, pos)
    end
  end

  # -- Keep a trailing prefix of "<event" when discarding junk ---------------

  defp keep_trailing_prefix(buffer, scan_pos) do
    # Only keep bytes from scan_pos onward that might be a partial "<event"
    if scan_pos >= byte_size(buffer) do
      <<>>
    else
      tail = binary_part(buffer, scan_pos, byte_size(buffer) - scan_pos)
      find_partial_event_prefix(tail)
    end
  end

  @prefixes ["<even", "<eve", "<ev", "<e", "<"]

  defp find_partial_event_prefix(tail) do
    Enum.find_value(@prefixes, <<>>, fn prefix ->
      if String.ends_with?(tail, prefix), do: prefix
    end)
  end
end
