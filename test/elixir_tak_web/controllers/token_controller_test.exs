defmodule ElixirTAKWeb.TokenControllerTest do
  use ElixirTAKWeb.ConnCase, async: false

  alias ElixirTAK.Auth.TokenStore

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ElixirTAK.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), TokenStore)
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), ElixirTAK.Auth.AuditLog)

    :ets.delete_all_objects(:api_tokens)
    {:ok, raw_token, _} = TokenStore.create("admin-token", "admin")
    {:ok, token: raw_token}
  end

  defp auth(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/admin/tokens" do
    test "creates a new token", %{conn: conn, token: token} do
      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/tokens", %{name: "new-token", role: "operator"})

      resp = json_response(conn, 201)
      assert resp["name"] == "new-token"
      assert resp["role"] == "operator"
      assert is_binary(resp["token"])
    end

    test "rejects missing name", %{conn: conn, token: token} do
      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/tokens", %{role: "viewer"})

      assert json_response(conn, 400)["error"] =~ "name"
    end

    test "rejects invalid role", %{conn: conn, token: token} do
      conn =
        conn
        |> auth(token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/tokens", %{name: "bad", role: "superadmin"})

      assert json_response(conn, 400)["error"] =~ "Invalid role"
    end

    test "non-admin cannot create tokens", %{conn: conn} do
      :ets.delete_all_objects(:api_tokens)
      {:ok, viewer_token, _} = TokenStore.create("viewer", "viewer")

      conn =
        conn
        |> auth(viewer_token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/tokens", %{name: "nope", role: "viewer"})

      assert json_response(conn, 403)
    end
  end

  describe "GET /api/admin/tokens" do
    test "lists tokens", %{conn: conn, token: token} do
      conn = conn |> auth(token) |> get("/api/admin/tokens")
      resp = json_response(conn, 200)
      assert resp["count"] >= 1
    end
  end

  describe "DELETE /api/admin/tokens/:id" do
    test "revokes a token", %{conn: conn, token: token} do
      {:ok, _, record} = TokenStore.create("to-revoke", "viewer")

      conn = conn |> auth(token) |> delete("/api/admin/tokens/#{record.id}")
      assert json_response(conn, 200)["status"] == "ok"
    end
  end

  describe "GET /api/admin/audit" do
    test "returns audit entries", %{conn: conn, token: token} do
      conn = conn |> auth(token) |> get("/api/admin/audit")
      resp = json_response(conn, 200)
      assert is_list(resp["entries"])
    end
  end
end
