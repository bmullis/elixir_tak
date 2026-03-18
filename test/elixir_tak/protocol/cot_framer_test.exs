defmodule ElixirTAK.Protocol.CotFramerTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.CotFramer

  @simple_event ~s(<event uid="test-1" type="a-f-G" version="2.0"><point lat="0.0" lon="0.0" hae="0.0" ce="0.0" le="0.0"/></event>)

  @full_event """
  <event uid="ANDROID-abc123" type="a-f-G-U-C" how="m-g"
         time="2024-01-15T12:00:00Z" start="2024-01-15T12:00:00Z"
         stale="2024-01-15T12:05:00Z" version="2.0">
    <point lat="38.8977" lon="-77.0365" hae="10.5" ce="9999999" le="9999999"/>
    <detail>
      <contact callsign="ALPHA-1"/>
      <__group name="Cyan" role="Team Lead"/>
      <track speed="2.5" course="180.0"/>
    </detail>
  </event>
  """

  describe "new/0" do
    test "returns a fresh framer" do
      framer = CotFramer.new()
      assert framer.buffer == <<>>
      assert framer.depth == 0
    end
  end

  describe "push/2 — single event" do
    test "extracts a complete simple event in one push" do
      {events, framer} = CotFramer.new() |> CotFramer.push(@simple_event)

      assert length(events) == 1
      assert hd(events) == @simple_event
      assert framer.depth == 0
      assert framer.event_start == nil
    end

    test "extracts a full event with nested detail elements" do
      {events, framer} = CotFramer.new() |> CotFramer.push(@full_event)

      assert length(events) == 1
      assert framer.depth == 0
      # Verify the extracted event can be parsed
      assert {:ok, _} = ElixirTAK.Protocol.CotParser.parse(hd(events))
    end
  end

  describe "push/2 — split across multiple pushes" do
    test "event split mid-tag" do
      # Split in the middle of <point
      {first, second} = String.split_at(@simple_event, 40)

      {events1, framer} = CotFramer.new() |> CotFramer.push(first)
      assert events1 == []

      {events2, _framer} = CotFramer.push(framer, second)
      assert length(events2) == 1
    end

    test "event split between point and detail" do
      {pos, _} = :binary.match(@full_event, "<detail")
      {first, second} = String.split_at(@full_event, pos)

      {[], framer} = CotFramer.new() |> CotFramer.push(first)
      {events, _} = CotFramer.push(framer, second)
      assert length(events) == 1
    end

    test "event split across three pushes" do
      len = byte_size(@full_event)
      third = div(len, 3)

      chunk1 = binary_part(@full_event, 0, third)
      chunk2 = binary_part(@full_event, third, third)
      chunk3 = binary_part(@full_event, third * 2, len - third * 2)

      {[], f1} = CotFramer.new() |> CotFramer.push(chunk1)
      {[], f2} = CotFramer.push(f1, chunk2)
      {events, _} = CotFramer.push(f2, chunk3)

      assert length(events) == 1
      assert {:ok, _} = ElixirTAK.Protocol.CotParser.parse(hd(events))
    end

    test "split right at </event> boundary" do
      # Split just before </event>
      {pos, _} = :binary.match(@full_event, "</event>")
      {first, second} = String.split_at(@full_event, pos)

      {[], framer} = CotFramer.new() |> CotFramer.push(first)
      {events, _} = CotFramer.push(framer, second)
      assert length(events) == 1
    end
  end

  describe "push/2 — multiple events" do
    test "two events concatenated in one push" do
      input = @simple_event <> @simple_event

      {events, framer} = CotFramer.new() |> CotFramer.push(input)

      assert length(events) == 2
      assert Enum.all?(events, &(&1 == @simple_event))
      assert framer.depth == 0
    end

    test "three events concatenated" do
      input = @simple_event <> @full_event <> @simple_event

      {events, _framer} = CotFramer.new() |> CotFramer.push(input)

      assert length(events) == 3
    end

    test "two events with whitespace between them" do
      input = @simple_event <> "\n  \r\n  " <> @simple_event

      {events, _} = CotFramer.new() |> CotFramer.push(input)

      assert length(events) == 2
    end

    test "first event complete, second split across push" do
      second_event = @simple_event
      {second_first, second_rest} = String.split_at(second_event, 20)

      input1 = @simple_event <> second_first

      {events1, framer} = CotFramer.new() |> CotFramer.push(input1)
      assert length(events1) == 1

      {events2, _} = CotFramer.push(framer, second_rest)
      assert length(events2) == 1
    end
  end

  describe "push/2 — edge cases" do
    test "empty push returns no events" do
      {events, framer} = CotFramer.new() |> CotFramer.push(<<>>)
      assert events == []
      assert framer.depth == 0
    end

    test "multiple empty pushes" do
      {[], f1} = CotFramer.new() |> CotFramer.push(<<>>)
      {[], f2} = CotFramer.push(f1, <<>>)
      {events, _} = CotFramer.push(f2, @simple_event)
      assert length(events) == 1
    end

    test "junk bytes before event are discarded" do
      input = "some junk data\n\n" <> @simple_event

      {events, _} = CotFramer.new() |> CotFramer.push(input)
      assert length(events) == 1
      assert hd(events) == @simple_event
    end

    test "whitespace and junk between events" do
      input = "garbage" <> @simple_event <> "\n\njunk\n" <> @simple_event

      {events, _} = CotFramer.new() |> CotFramer.push(input)
      assert length(events) == 2
    end

    test "partial prefix is preserved across pushes" do
      # Send just "<ev" then the rest
      {[], framer} = CotFramer.new() |> CotFramer.push("<ev")
      {events, _} = CotFramer.push(framer, String.slice(@simple_event, 3..-1//1))
      assert length(events) == 1
    end

    test "self-closing event tag" do
      input = ~s(<event uid="ping" type="t-x-c-t" how="h-g-i-g-o"/>)

      {events, framer} = CotFramer.new() |> CotFramer.push(input)
      assert length(events) == 1
      assert hd(events) == input
      assert framer.depth == 0
    end

    test "does not confuse <eventually> with <event>" do
      # A tag like <eventually> should not trigger event detection
      input = "<root><eventually>data</eventually></root>" <> @simple_event

      {events, _} = CotFramer.new() |> CotFramer.push(input)
      assert length(events) == 1
      assert hd(events) == @simple_event
    end
  end

  describe "push/2 — buffer overflow" do
    test "returns error when buffer exceeds max size" do
      framer = CotFramer.new()
      # Start an event that never closes
      {[], framer} = CotFramer.push(framer, "<event uid=\"x\" type=\"y\">")

      # Push 1MB+ of data without closing
      big_chunk = String.duplicate("x", 1_048_576)
      assert {:error, :buffer_overflow, fresh} = CotFramer.push(framer, big_chunk)
      assert fresh.depth == 0
      assert fresh.buffer == <<>>
    end
  end

  describe "push/2 — quoted attribute values with special chars" do
    test "handles > inside quoted attribute" do
      # A callsign containing > (weird but possible)
      input =
        ~s(<event uid="test" type="a-f-G" version="2.0"><point lat="0" lon="0" hae="0" ce="0" le="0"/><detail><contact callsign="alpha>bravo"/></detail></event>)

      {events, _} = CotFramer.new() |> CotFramer.push(input)
      assert length(events) == 1
    end
  end
end
