defmodule ElixirTAK.Protocol.CotValidatorTest do
  use ExUnit.Case, async: true

  alias ElixirTAK.Protocol.{CotEvent, CotValidator}

  @valid_event %CotEvent{
    uid: "test-1",
    type: "a-f-G-U-C",
    how: "m-g",
    start: ~U[2024-01-15 12:00:00Z],
    stale: ~U[2024-01-15 12:05:00Z],
    point: %{lat: 38.8977, lon: -77.0365, hae: 10.5, ce: nil, le: nil}
  }

  describe "validate/1" do
    test "accepts a valid event" do
      assert {:ok, @valid_event} == CotValidator.validate(@valid_event)
    end

    test "accepts a minimal event with no start/stale" do
      event = %CotEvent{
        uid: "min-1",
        type: "a-f-G",
        point: %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil}
      }

      assert {:ok, ^event} = CotValidator.validate(event)
    end

    test "accepts boundary lat/lon values" do
      for {lat, lon} <- [{-90, -180}, {90, 180}, {0, 0}, {-90, 180}, {90, -180}] do
        event = %{@valid_event | point: %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil}}
        assert {:ok, _} = CotValidator.validate(event)
      end
    end

    test "rejects lat out of range" do
      event = %{@valid_event | point: %{@valid_event.point | lat: 91.0}}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_lat in reasons
    end

    test "rejects negative lat out of range" do
      event = %{@valid_event | point: %{@valid_event.point | lat: -90.1}}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_lat in reasons
    end

    test "rejects lon out of range" do
      event = %{@valid_event | point: %{@valid_event.point | lon: 181.0}}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_lon in reasons
    end

    test "rejects negative lon out of range" do
      event = %{@valid_event | point: %{@valid_event.point | lon: -180.1}}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_lon in reasons
    end

    test "rejects start after stale" do
      event = %{@valid_event | start: ~U[2024-01-15 13:00:00Z], stale: ~U[2024-01-15 12:00:00Z]}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :start_after_stale in reasons
    end

    test "accepts start equal to stale" do
      event = %{@valid_event | start: ~U[2024-01-15 12:00:00Z], stale: ~U[2024-01-15 12:00:00Z]}
      assert {:ok, _} = CotValidator.validate(event)
    end

    test "skips start/stale check when start is nil" do
      event = %{@valid_event | start: nil, stale: ~U[2024-01-15 12:05:00Z]}
      assert {:ok, _} = CotValidator.validate(event)
    end

    test "skips start/stale check when stale is nil" do
      event = %{@valid_event | start: ~U[2024-01-15 12:00:00Z], stale: nil}
      assert {:ok, _} = CotValidator.validate(event)
    end

    test "rejects empty type" do
      event = %{@valid_event | type: ""}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_type in reasons
    end

    test "rejects type with leading dash" do
      event = %{@valid_event | type: "-a-f"}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_type in reasons
    end

    test "rejects type with trailing dash" do
      event = %{@valid_event | type: "a-f-"}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_type in reasons
    end

    test "rejects type with consecutive dashes" do
      event = %{@valid_event | type: "a--f"}
      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_type in reasons
    end

    test "accepts single-segment type" do
      event = %{@valid_event | type: "b"}
      assert {:ok, _} = CotValidator.validate(event)
    end

    test "collects multiple errors" do
      event = %{
        @valid_event
        | type: "",
          point: %{lat: 999, lon: 999, hae: nil, ce: nil, le: nil},
          start: ~U[2024-01-15 13:00:00Z],
          stale: ~U[2024-01-15 12:00:00Z]
      }

      assert {:error, reasons} = CotValidator.validate(event)
      assert :invalid_lat in reasons
      assert :invalid_lon in reasons
      assert :start_after_stale in reasons
      assert :invalid_type in reasons
    end
  end
end
