defmodule ElixirTAKWeb.MissionControllerTest do
  use ElixirTAKWeb.ConnCase, async: false

  alias ElixirTAK.Auth.TokenStore
  alias ElixirTAK.Missions.MissionStore

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ElixirTAK.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # Allow persistent GenServers to use sandbox
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), TokenStore)
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), MissionStore)
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), ElixirTAK.Auth.AuditLog)

    :ets.delete_all_objects(:api_tokens)
    :ets.delete_all_objects(:mission_cache)

    {:ok, raw_token, _record} = TokenStore.create("test-admin", "admin")
    {:ok, token: raw_token}
  end

  defp auth(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "bootstrap mode (no tokens)" do
    setup do
      :ets.delete_all_objects(:api_tokens)
      :ok
    end

    test "allows unauthenticated access when no tokens exist", %{conn: conn} do
      conn = get(conn, "/api/missions")
      assert json_response(conn, 200)["count"] == 0
    end
  end

  describe "authentication" do
    test "rejects requests without token", %{conn: conn, token: _token} do
      conn = get(conn, "/api/missions")
      assert json_response(conn, 401)["error"] =~ "Invalid"
    end

    test "accepts valid token", %{conn: conn, token: token} do
      conn = conn |> auth(token) |> get("/api/missions")
      assert json_response(conn, 200)
    end
  end

  describe "POST /api/missions" do
    test "creates a mission", %{conn: conn, token: token} do
      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/missions", %{name: "Recon Alpha", description: "Patrol route A"})

      resp = json_response(conn, 201)
      assert resp["name"] == "Recon Alpha"
      assert resp["description"] == "Patrol route A"
    end

    test "rejects missing name", %{conn: conn, token: token} do
      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/missions", %{description: "no name"})

      assert json_response(conn, 422)["error"] == "Validation failed"
    end

    test "viewers cannot create missions", %{conn: conn} do
      :ets.delete_all_objects(:api_tokens)
      {:ok, viewer_token, _} = TokenStore.create("viewer", "viewer")

      conn =
        conn
        |> auth(viewer_token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/missions", %{name: "Blocked"})

      assert json_response(conn, 403)["error"] =~ "Insufficient"
    end
  end

  describe "GET /api/missions" do
    test "lists missions", %{conn: conn, token: token} do
      MissionStore.create(%{name: "List Test A"})
      MissionStore.create(%{name: "List Test B"})

      conn = conn |> auth(token) |> get("/api/missions")
      resp = json_response(conn, 200)
      assert resp["count"] == 2
    end
  end

  describe "GET /api/missions/:name" do
    test "shows a mission with contents", %{conn: conn, token: token} do
      MissionStore.create(%{name: "Detail Test"})

      MissionStore.add_content("Detail Test", %{
        content_type: "data_package",
        content_uid: "pkg-1",
        data_package_hash: "hash123"
      })

      conn = conn |> auth(token) |> get("/api/missions/Detail Test")
      resp = json_response(conn, 200)
      assert resp["name"] == "Detail Test"
      assert length(resp["contents"]) == 1
    end

    test "returns 404 for missing mission", %{conn: conn, token: token} do
      conn = conn |> auth(token) |> get("/api/missions/nope")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "DELETE /api/missions/:name" do
    test "deletes a mission", %{conn: conn, token: token} do
      MissionStore.create(%{name: "To Delete"})
      conn = conn |> auth(token) |> delete("/api/missions/To Delete")
      assert json_response(conn, 200)["status"] == "ok"
    end
  end

  describe "POST /api/missions/:name/subscription" do
    test "subscribes a client", %{conn: conn, token: token} do
      MissionStore.create(%{name: "Sub Mission"})

      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/missions/Sub Mission/subscription", %{client_uid: "atak-1"})

      resp = json_response(conn, 200)
      assert length(resp["subscriptions"]) == 1
    end

    test "rejects missing client_uid", %{conn: conn, token: token} do
      MissionStore.create(%{name: "Bad Sub"})

      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/missions/Bad Sub/subscription", %{})

      assert json_response(conn, 400)["error"] =~ "client_uid"
    end
  end
end
