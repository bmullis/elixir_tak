defmodule ElixirTAKWeb.DashboardApiController do
  @moduledoc "REST API for the React dashboard."

  use Phoenix.Controller, formats: [:json]

  @doc "GET /api/dashboard/snapshot - full initial state"
  def snapshot(conn, _params) do
    json(conn, ElixirTAKWeb.DashboardChannel.build_snapshot())
  end
end
