defmodule ElixirTAKWeb.Plugs.RequireRole do
  @moduledoc """
  Plug that enforces minimum role level for an endpoint.

  Role hierarchy: admin > operator > viewer.

  Usage in a controller:
      plug ElixirTAKWeb.Plugs.RequireRole, "operator" when action in [:create, :update]
      plug ElixirTAKWeb.Plugs.RequireRole, "admin" when action in [:delete]
  """

  import Plug.Conn

  @behaviour Plug

  @role_levels %{"admin" => 3, "operator" => 2, "viewer" => 1}

  @impl true
  def init(required_role) when is_binary(required_role), do: required_role

  @impl true
  def call(conn, required_role) do
    current_role = conn.assigns[:api_role]
    current_level = Map.get(@role_levels, current_role, 0)
    required_level = Map.get(@role_levels, required_role, 0)

    if current_level >= required_level do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{error: "Insufficient permissions", required: required_role})
      )
      |> halt()
    end
  end
end
