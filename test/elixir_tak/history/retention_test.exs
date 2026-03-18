defmodule ElixirTAK.History.RetentionTest do
  use ElixirTAK.DataCase, async: false

  alias ElixirTAK.History.{EventRecord, Retention}

  defp insert_event!(attrs) do
    now = DateTime.utc_now()

    defaults = %{
      id: Ecto.UUID.generate(),
      uid: "uid-1",
      type: "a-f-G-U-C",
      how: "m-g",
      callsign: "Test",
      group_name: "Cyan",
      lat: 33.5,
      lon: -111.9,
      event_time: now,
      stale_time: DateTime.add(now, 600, :second),
      inserted_at: now,
      updated_at: now
    }

    {1, _} = Repo.insert_all(EventRecord, [Map.merge(defaults, Map.new(attrs))])
  end

  test "deletes events older than max_age_hours" do
    # Test config sets max_age_hours: 1
    old_time = DateTime.add(DateTime.utc_now(), -7200, :second)
    recent_time = DateTime.utc_now()

    insert_event!(uid: "old", event_time: old_time)
    insert_event!(uid: "recent", event_time: recent_time)

    deleted = Retention.run_cleanup()
    assert deleted == 1

    remaining = Repo.all(EventRecord)
    assert length(remaining) == 1
    assert hd(remaining).uid == "recent"
  end

  test "recent events survive retention" do
    insert_event!(uid: "fresh-1", event_time: DateTime.utc_now())
    insert_event!(uid: "fresh-2", event_time: DateTime.utc_now())

    deleted = Retention.run_cleanup()
    assert deleted == 0
    assert Repo.aggregate(EventRecord, :count) == 2
  end
end
