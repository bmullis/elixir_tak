defmodule ElixirTAK.Missions.MissionStoreTest do
  use ElixirTAK.DataCase, async: false

  alias ElixirTAK.Missions.MissionStore

  setup do
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), MissionStore)

    :ets.delete_all_objects(:mission_cache)
    :ok
  end

  describe "create/1" do
    test "creates a mission and caches it" do
      assert {:ok, mission} = MissionStore.create(%{name: "Alpha Patrol"})
      assert mission.name == "Alpha Patrol"
      assert {:ok, _} = MissionStore.get("Alpha Patrol")
    end

    test "rejects duplicate names" do
      MissionStore.create(%{name: "Unique Op"})
      assert {:error, _changeset} = MissionStore.create(%{name: "Unique Op"})
    end

    test "validates name is required" do
      assert {:error, _changeset} = MissionStore.create(%{description: "no name"})
    end
  end

  describe "get/1" do
    test "returns :not_found for missing missions" do
      assert :not_found = MissionStore.get("nope")
    end
  end

  describe "list/0" do
    test "returns all missions" do
      MissionStore.create(%{name: "Mission A"})
      MissionStore.create(%{name: "Mission B"})
      missions = MissionStore.list()
      names = Enum.map(missions, & &1.name)
      assert "Mission A" in names
      assert "Mission B" in names
    end
  end

  describe "delete/1" do
    test "removes a mission" do
      MissionStore.create(%{name: "To Delete"})
      assert :ok = MissionStore.delete("To Delete")
      assert :not_found = MissionStore.get("To Delete")
    end

    test "returns :not_found for missing" do
      assert :not_found = MissionStore.delete("ghost")
    end
  end

  describe "contents" do
    test "adds and retrieves content" do
      {:ok, _} = MissionStore.create(%{name: "Content Test"})

      {:ok, mission} =
        MissionStore.add_content("Content Test", %{
          content_type: "data_package",
          content_uid: "pkg-001",
          data_package_hash: "abc123"
        })

      assert length(mission.contents) == 1
      assert hd(mission.contents).content_uid == "pkg-001"
    end

    test "removes content by uid" do
      {:ok, _} = MissionStore.create(%{name: "Remove Content"})

      MissionStore.add_content("Remove Content", %{
        content_type: "marker",
        content_uid: "marker-1"
      })

      MissionStore.remove_content("Remove Content", "marker-1")
      {:ok, mission} = MissionStore.get("Remove Content")
      assert mission.contents == []
    end
  end

  describe "subscriptions" do
    test "subscribes and lists subscribers" do
      {:ok, _} = MissionStore.create(%{name: "Sub Test"})
      {:ok, mission} = MissionStore.subscribe("Sub Test", "client-abc")
      assert length(mission.subscriptions) == 1
      assert hd(mission.subscriptions).client_uid == "client-abc"
    end

    test "unsubscribes a client" do
      {:ok, _} = MissionStore.create(%{name: "Unsub Test"})
      MissionStore.subscribe("Unsub Test", "client-xyz")
      MissionStore.unsubscribe("Unsub Test", "client-xyz")
      {:ok, mission} = MissionStore.get("Unsub Test")
      assert mission.subscriptions == []
    end

    test "rejects duplicate subscriptions" do
      {:ok, _} = MissionStore.create(%{name: "Dup Sub"})
      {:ok, _} = MissionStore.subscribe("Dup Sub", "client-1")
      assert {:error, _} = MissionStore.subscribe("Dup Sub", "client-1")
    end
  end
end
