defmodule ElixirTAK.History.QueriesTest do
  use ElixirTAK.DataCase, async: false

  alias ElixirTAK.History.{EventRecord, Queries}

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
      hae: 0.0,
      speed: 5.0,
      course: 90.0,
      raw_xml: "<event/>",
      event_time: now,
      stale_time: DateTime.add(now, 600, :second),
      inserted_at: now,
      updated_at: now
    }

    {1, _} = Repo.insert_all(EventRecord, [Map.merge(defaults, Map.new(attrs))])
  end

  describe "by_uid/2" do
    test "returns events for the given UID, newest first" do
      t1 = ~U[2025-01-01 00:00:00.000000Z]
      t2 = ~U[2025-01-01 01:00:00.000000Z]

      insert_event!(uid: "alpha", event_time: t1)
      insert_event!(uid: "alpha", event_time: t2)
      insert_event!(uid: "bravo", event_time: t1)

      results = Queries.by_uid("alpha")
      assert length(results) == 2
      assert hd(results).event_time == t2

      assert Queries.by_uid("bravo") |> length() == 1
      assert Queries.by_uid("missing") == []
    end
  end

  describe "by_time_range/3" do
    test "returns events within the time window" do
      t1 = ~U[2025-01-01 00:00:00.000000Z]
      t2 = ~U[2025-01-02 00:00:00.000000Z]
      t3 = ~U[2025-01-03 00:00:00.000000Z]

      insert_event!(event_time: t1)
      insert_event!(event_time: t2)
      insert_event!(event_time: t3)

      results =
        Queries.by_time_range(~U[2025-01-01 12:00:00.000000Z], ~U[2025-01-02 12:00:00.000000Z])

      assert length(results) == 1
      assert hd(results).event_time == t2
    end
  end

  describe "by_type/2" do
    test "filters by type prefix" do
      insert_event!(type: "a-f-G-U-C")
      insert_event!(type: "a-h-G")
      insert_event!(type: "b-t-f")

      assert Queries.by_type("a-f-") |> length() == 1
      assert Queries.by_type("a-") |> length() == 2
      assert Queries.by_type("b-t-") |> length() == 1
    end
  end

  describe "by_bbox/5" do
    test "returns events within bounding box" do
      insert_event!(lat: 33.5, lon: -111.9)
      insert_event!(lat: 40.0, lon: -74.0)
      insert_event!(lat: 34.0, lon: -112.0)

      results = Queries.by_bbox(33.0, 35.0, -113.0, -111.0)
      assert length(results) == 2
    end

    test "excludes events outside bounding box" do
      insert_event!(lat: 50.0, lon: 0.0)

      assert Queries.by_bbox(33.0, 35.0, -113.0, -111.0) == []
    end
  end

  describe "track/2" do
    test "returns points in time order (oldest first)" do
      t1 = ~U[2025-01-01 00:00:00.000000Z]
      t2 = ~U[2025-01-01 01:00:00.000000Z]
      t3 = ~U[2025-01-01 02:00:00.000000Z]

      insert_event!(uid: "tracker", event_time: t3, lat: 33.5, lon: -111.9)
      insert_event!(uid: "tracker", event_time: t1, lat: 33.0, lon: -111.0)
      insert_event!(uid: "tracker", event_time: t2, lat: 33.2, lon: -111.5)

      results = Queries.track("tracker")
      assert length(results) == 3
      times = Enum.map(results, & &1.event_time)
      assert times == [t1, t2, t3]
    end

    test "respects since/until filters" do
      insert_event!(uid: "t", event_time: ~U[2025-01-01 00:00:00.000000Z])
      insert_event!(uid: "t", event_time: ~U[2025-01-02 00:00:00.000000Z])
      insert_event!(uid: "t", event_time: ~U[2025-01-03 00:00:00.000000Z])

      results =
        Queries.track("t",
          since: ~U[2025-01-01 12:00:00.000000Z],
          until: ~U[2025-01-02 12:00:00.000000Z]
        )

      assert length(results) == 1
    end
  end

  describe "latest_per_uid/1" do
    test "returns most recent event per UID" do
      insert_event!(uid: "a", event_time: ~U[2025-01-01 00:00:00.000000Z])
      insert_event!(uid: "a", event_time: ~U[2025-01-02 00:00:00.000000Z])
      insert_event!(uid: "b", event_time: ~U[2025-01-01 00:00:00.000000Z])

      results = Queries.latest_per_uid()
      assert length(results) == 2

      a_record = Enum.find(results, &(&1.uid == "a"))
      assert a_record.event_time == ~U[2025-01-02 00:00:00.000000Z]
    end
  end
end
