defmodule ElixirTAKWeb.TokenController do
  @moduledoc "REST API for managing API tokens."

  use Phoenix.Controller, formats: [:json]

  alias ElixirTAK.Auth.{TokenStore, AuditLog, ApiToken}

  plug(ElixirTAKWeb.Plugs.RequireRole, "admin")

  @doc "POST /api/admin/tokens - create a new API token"
  def create(conn, params) do
    name = params["name"]
    role = params["role"] || "viewer"

    if is_nil(name) or name == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "name is required"})
    else
      if role not in ApiToken.roles() do
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid role. Must be one of: #{Enum.join(ApiToken.roles(), ", ")}"})
      else
        expires_at =
          case params["expires_in_days"] do
            days when is_integer(days) and days > 0 ->
              DateTime.utc_now()
              |> DateTime.add(days * 86_400, :second)
              |> DateTime.truncate(:microsecond)

            _ ->
              nil
          end

        case TokenStore.create(name, role, expires_at: expires_at) do
          {:ok, raw_token, record} ->
            AuditLog.record("token.create", conn, "api_token", record.id, %{
              name: name,
              role: role
            })

            conn
            |> put_status(:created)
            |> json(%{
              token: raw_token,
              id: record.id,
              name: record.name,
              role: record.role,
              expires_at: record.expires_at && DateTime.to_iso8601(record.expires_at),
              message: "Save this token now. It cannot be retrieved again."
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to create token", details: inspect(changeset.errors)})
        end
      end
    end
  end

  @doc "GET /api/admin/tokens - list all tokens"
  def index(conn, _params) do
    tokens =
      TokenStore.list()
      |> Enum.map(fn t ->
        %{
          id: t.id,
          name: t.name,
          role: t.role,
          active: t.active,
          last_used_at: t.last_used_at && DateTime.to_iso8601(t.last_used_at),
          expires_at: t.expires_at && DateTime.to_iso8601(t.expires_at),
          created_at: t.inserted_at && DateTime.to_iso8601(t.inserted_at)
        }
      end)

    json(conn, %{count: length(tokens), tokens: tokens})
  end

  @doc "DELETE /api/admin/tokens/:id - revoke a token"
  def revoke(conn, %{"id" => id}) do
    case TokenStore.revoke(id) do
      :ok ->
        AuditLog.record("token.revoke", conn, "api_token", id)
        json(conn, %{status: "ok", message: "Token revoked"})

      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})
    end
  end

  @doc "GET /api/admin/audit - query audit log"
  def audit_log(conn, params) do
    opts =
      []
      |> then(fn o ->
        if params["action"], do: Keyword.put(o, :action, params["action"]), else: o
      end)
      |> then(fn o ->
        if params["actor"], do: Keyword.put(o, :actor, params["actor"]), else: o
      end)
      |> Keyword.put(:limit, parse_int(params["limit"], 100))

    entries =
      AuditLog.recent(opts)
      |> Enum.map(fn e ->
        %{
          id: e.id,
          action: e.action,
          actor: e.actor,
          role: e.role,
          resource_type: e.resource_type,
          resource_id: e.resource_id,
          details: if(e.details, do: Jason.decode!(e.details)),
          timestamp: e.inserted_at && DateTime.to_iso8601(e.inserted_at)
        }
      end)

    json(conn, %{count: length(entries), entries: entries})
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
end
