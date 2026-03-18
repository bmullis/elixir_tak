defmodule ElixirTAKWeb.DashboardController do
  @moduledoc "Serves the React dashboard SPA."

  use Phoenix.Controller, formats: [:html]

  @doc "Serve the React app's index.html for all /dashboard/* routes."
  def index(conn, _params) do
    dashboard_path = Application.app_dir(:elixir_tak, "priv/static/dashboard/index.html")

    if File.exists?(dashboard_path) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, dashboard_path)
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, """
      <!DOCTYPE html>
      <html><head><title>ElixirTAK Dashboard</title></head>
      <body style="background:#09090b;color:#a1a1aa;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
        <div style="text-align:center">
          <h1 style="color:#e4e4e7">ElixirTAK Dashboard</h1>
          <p>React app not built yet. Run: <code style="color:#06b6d4">cd assets/dashboard && pnpm build</code></p>
        </div>
      </body></html>
      """)
    end
  end
end
