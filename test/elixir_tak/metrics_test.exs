defmodule ElixirTAK.MetricsTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.Metrics

  test "get_stats returns expected shape" do
    stats = Metrics.get_stats()

    assert is_integer(stats.total_events)
    assert is_integer(stats.events_per_second)
    assert is_integer(stats.events_per_minute)
    assert is_integer(stats.connected_clients)
    assert is_integer(stats.sa_cached)
    assert is_integer(stats.chat_cached)
    assert is_integer(stats.uptime_seconds)
    assert is_float(stats.memory_mb)
  end

  test "record_event increments total" do
    before = Metrics.get_stats().total_events

    Metrics.record_event("a-f-G-U-C")
    Metrics.record_event("a-f-G-U-C")
    Metrics.record_event("b-t-f")

    stats = Metrics.get_stats()
    assert stats.total_events >= before + 3
  end
end
