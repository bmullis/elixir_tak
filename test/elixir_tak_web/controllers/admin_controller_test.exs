defmodule ElixirTAKWeb.AdminControllerTest do
  use ElixirTAKWeb.ConnCase, async: false

  alias ElixirTAK.ClientRegistry

  setup do
    :ets.delete_all_objects(:sa_cache)
    :ets.delete_all_objects(:client_registry)
    # Clear tokens to keep bootstrap mode (no auth required)
    :ets.delete_all_objects(:api_tokens)
    :ok
  end

  # -- Health ----------------------------------------------------------------

  describe "GET /api/admin/health" do
    test "returns 200 with health info", %{conn: conn} do
      conn = get(conn, "/api/admin/health")
      body = json_response(conn, 200)

      assert body["status"] == "ok"
      assert is_integer(body["uptime_seconds"])
      assert is_integer(body["connected_clients"])
      assert is_integer(body["data_packages"])
      assert is_map(body["memory"])
      assert is_integer(body["memory"]["total"])
    end
  end

  # -- Clients ---------------------------------------------------------------

  describe "GET /api/admin/clients" do
    test "returns empty list with no connections", %{conn: conn} do
      conn = get(conn, "/api/admin/clients")
      body = json_response(conn, 200)

      assert body["count"] == 0
      assert body["clients"] == []
    end

    test "returns client data from registry", %{conn: conn} do
      ClientRegistry.register("test-uid-123", %{
        callsign: "ALPHA-1",
        group: "Cyan",
        peer: {{192, 168, 1, 10}, 54321},
        cert_cn: "alpha-cert",
        handler_pid: self()
      })

      conn = get(conn, "/api/admin/clients")
      body = json_response(conn, 200)

      assert body["count"] == 1
      [client] = body["clients"]
      assert client["uid"] == "test-uid-123"
      assert client["callsign"] == "ALPHA-1"
      assert client["group"] == "Cyan"
      assert client["peer"] == "192.168.1.10:54321"
      assert client["cert_cn"] == "alpha-cert"
      assert is_binary(client["connected_at"])
    end
  end

  describe "DELETE /api/admin/clients/:uid" do
    test "sends disconnect to registered client", %{conn: conn} do
      ClientRegistry.register("test-uid-456", %{
        callsign: "BRAVO-1",
        group: "Cyan",
        peer: {{127, 0, 0, 1}, 12345},
        cert_cn: nil,
        handler_pid: self()
      })

      conn = delete(conn, "/api/admin/clients/test-uid-456")
      body = json_response(conn, 200)

      assert body["status"] == "ok"
      assert_receive :admin_disconnect
    end

    test "returns 404 for unknown client", %{conn: conn} do
      conn = delete(conn, "/api/admin/clients/nonexistent-uid")
      body = json_response(conn, 404)

      assert body["error"] == "Client not found"
    end
  end

  # -- Groups ----------------------------------------------------------------

  describe "GET /api/admin/groups" do
    test "returns empty list with no clients", %{conn: conn} do
      conn = get(conn, "/api/admin/groups")
      body = json_response(conn, 200)

      assert body["count"] == 0
      assert body["groups"] == []
    end

    test "groups clients by their group", %{conn: conn} do
      ClientRegistry.register("uid-1", %{
        callsign: "ALPHA-1",
        group: "Cyan",
        peer: nil,
        cert_cn: nil,
        handler_pid: self()
      })

      ClientRegistry.register("uid-2", %{
        callsign: "ALPHA-2",
        group: "Cyan",
        peer: nil,
        cert_cn: nil,
        handler_pid: self()
      })

      ClientRegistry.register("uid-3", %{
        callsign: "BRAVO-1",
        group: "Yellow",
        peer: nil,
        cert_cn: nil,
        handler_pid: self()
      })

      ClientRegistry.register("uid-4", %{
        callsign: "CHARLIE-1",
        group: nil,
        peer: nil,
        cert_cn: nil,
        handler_pid: self()
      })

      conn = get(conn, "/api/admin/groups")
      body = json_response(conn, 200)

      assert body["count"] == 3
      groups = body["groups"]

      ungrouped = Enum.find(groups, &(&1["name"] == "(ungrouped)"))
      assert ungrouped["member_count"] == 1

      cyan = Enum.find(groups, &(&1["name"] == "Cyan"))
      assert cyan["member_count"] == 2

      yellow = Enum.find(groups, &(&1["name"] == "Yellow"))
      assert yellow["member_count"] == 1
    end
  end

  describe "POST /api/admin/groups/:name/announce" do
    test "broadcasts announcement as chat event", %{conn: conn} do
      Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/groups/Cyan/announce", %{"message" => "Test announcement"})

      body = json_response(conn, 200)
      assert body["status"] == "ok"

      assert_receive {:cot_broadcast, _uid, event, "Cyan"}
      assert event.type == "b-t-f"
      assert event.raw_detail =~ "Test announcement"
      assert event.raw_detail =~ "chatroom=\"Cyan\""
    end

    test "returns 400 when message is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/groups/Cyan/announce", %{})

      body = json_response(conn, 400)
      assert body["error"] == "message is required"
    end

    test "escapes XML special characters in message", %{conn: conn} do
      Phoenix.PubSub.subscribe(ElixirTAK.PubSub, "cot:broadcast")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/groups/Cyan/announce", %{"message" => "A < B & C > D"})

      json_response(conn, 200)

      assert_receive {:cot_broadcast, _uid, event, "Cyan"}
      assert event.raw_detail =~ "A &lt; B &amp; C &gt; D"
    end
  end

  # -- Config ----------------------------------------------------------------

  describe "GET /api/admin/config" do
    test "returns server configuration", %{conn: conn} do
      conn = get(conn, "/api/admin/config")
      body = json_response(conn, 200)

      assert is_integer(body["tcp_port"])
      assert is_integer(body["tls_port"])
      assert is_boolean(body["tls_enabled"])
      assert is_boolean(body["simulator"])
      assert is_binary(body["dashboard_callsign"])
      assert is_binary(body["dashboard_group"])
      assert is_map(body["federation"])
      assert is_boolean(body["federation"]["enabled"])
      assert is_map(body["retention"])
      assert is_integer(body["retention"]["max_age_hours"])
    end
  end

  describe "PUT /api/admin/config" do
    setup do
      original_callsign = Application.get_env(:elixir_tak, :dashboard_callsign)
      original_group = Application.get_env(:elixir_tak, :dashboard_group)

      on_exit(fn ->
        Application.put_env(:elixir_tak, :dashboard_callsign, original_callsign)
        Application.put_env(:elixir_tak, :dashboard_group, original_group)
      end)

      :ok
    end

    test "updates runtime configuration", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/admin/config", %{
          "dashboard_callsign" => "NewCallsign",
          "dashboard_group" => "Magenta"
        })

      body = json_response(conn, 200)
      assert body["status"] == "ok"
      assert "dashboard_callsign=NewCallsign" in body["updated"]
      assert "dashboard_group=Magenta" in body["updated"]

      assert Application.get_env(:elixir_tak, :dashboard_callsign) == "NewCallsign"
      assert Application.get_env(:elixir_tak, :dashboard_group) == "Magenta"
    end

    test "returns 400 when no recognized keys provided", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/admin/config", %{"bogus" => "value"})

      body = json_response(conn, 400)
      assert body["error"] =~ "No recognized"
    end
  end

  # -- Federation peers ------------------------------------------------------

  describe "GET /api/admin/federation/peers" do
    test "returns disabled status when federation is off", %{conn: conn} do
      conn = get(conn, "/api/admin/federation/peers")
      body = json_response(conn, 200)

      assert body["enabled"] == false
      assert body["peers"] == []
    end
  end

  describe "POST /api/admin/federation/peers" do
    test "returns 400 when federation is disabled", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/federation/peers", %{"action" => "add", "peer" => "tak2@host"})

      body = json_response(conn, 400)
      assert body["error"] =~ "not enabled"
    end
  end
end
