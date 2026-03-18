defmodule ElixirTAK.ClientRegistryTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.ClientRegistry

  setup do
    :ets.delete_all_objects(:client_registry)
    :ok
  end

  test "register and get_all" do
    ClientRegistry.register("UID-1", %{
      callsign: "ALPHA",
      group: "Cyan",
      peer: {{127, 0, 0, 1}, 1234},
      cert_cn: nil
    })

    clients = ClientRegistry.get_all()
    assert length(clients) == 1
    assert hd(clients).uid == "UID-1"
    assert hd(clients).callsign == "ALPHA"
    assert hd(clients).group == "Cyan"
    assert %DateTime{} = hd(clients).connected_at
  end

  test "count" do
    assert ClientRegistry.count() == 0

    ClientRegistry.register("UID-1", %{callsign: "A", group: nil, peer: nil, cert_cn: nil})
    assert ClientRegistry.count() == 1

    ClientRegistry.register("UID-2", %{callsign: "B", group: nil, peer: nil, cert_cn: nil})
    assert ClientRegistry.count() == 2
  end

  test "unregister removes client" do
    ClientRegistry.register("UID-1", %{callsign: "A", group: nil, peer: nil, cert_cn: nil})
    assert ClientRegistry.count() == 1

    ClientRegistry.unregister("UID-1")
    assert ClientRegistry.count() == 0
    assert ClientRegistry.get_all() == []
  end

  test "unregister nil is a no-op" do
    assert ClientRegistry.unregister(nil) == :ok
  end

  test "update merges fields" do
    ClientRegistry.register("UID-1", %{callsign: "A", group: nil, peer: nil, cert_cn: nil})
    ClientRegistry.update("UID-1", %{group: "Cyan"})

    [client] = ClientRegistry.get_all()
    assert client.group == "Cyan"
    assert client.callsign == "A"
  end

  test "update nonexistent uid is a no-op" do
    assert ClientRegistry.update("NOPE", %{group: "Cyan"}) == :ok
  end

  test "register broadcasts client_connected" do
    Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "dashboard:events")

    ClientRegistry.register("UID-1", %{callsign: "A", group: "Cyan", peer: nil, cert_cn: nil})

    assert_receive {:client_connected, "UID-1", %{callsign: "A"}}
  end

  test "unregister broadcasts client_disconnected" do
    Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "dashboard:events")

    ClientRegistry.register("UID-1", %{callsign: "A", group: nil, peer: nil, cert_cn: nil})
    ClientRegistry.unregister("UID-1")

    assert_receive {:client_disconnected, "UID-1"}
  end
end
