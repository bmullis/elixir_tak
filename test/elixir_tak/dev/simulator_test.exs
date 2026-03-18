defmodule ElixirTAK.Dev.SimulatorTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.Dev.Simulator
  alias ElixirTAK.{ClientRegistry, SACache}

  setup do
    :ets.delete_all_objects(:client_registry)
    :ets.delete_all_objects(:sa_cache)
    :ets.delete_all_objects(:chat_cache)
    :ok
  end

  test "starting the simulator populates SACache and ClientRegistry" do
    {:ok, pid} = start_supervised(Simulator)
    assert Process.alive?(pid)

    assert ClientRegistry.count() == 9
    assert length(SACache.get_all()) == 9

    clients = ClientRegistry.get_all()
    assert Enum.all?(clients, fn c -> String.starts_with?(c.uid, "SIM-") end)
  end

  test "stopping the simulator cleans up" do
    pid = start_supervised!({Simulator, []}, restart: :temporary)
    assert ClientRegistry.count() == 9

    GenServer.stop(pid, :normal)
    Process.sleep(50)

    assert ClientRegistry.count() == 0
    assert SACache.get_all() == []
  end

  test "simulator broadcasts position updates on PubSub" do
    Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")

    {:ok, _pid} = start_supervised(Simulator)

    # Should receive initial position broadcasts
    assert_receive {:cot_broadcast, "SIM-" <> _, _event, _group}, 1000
  end
end
