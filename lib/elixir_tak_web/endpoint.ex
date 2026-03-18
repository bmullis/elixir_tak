defmodule ElixirTAKWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :elixir_tak

  socket("/socket/dashboard", ElixirTAKWeb.DashboardSocket, websocket: true)

  # React dashboard static files (Vite build output: JS/CSS bundles + Cesium assets)
  plug(Plug.Static,
    at: "/dashboard/assets",
    from: {:elixir_tak, "priv/static/dashboard/assets"},
    gzip: false
  )

  plug(Plug.Static,
    at: "/dashboard/cesium",
    from: {:elixir_tak, "priv/static/dashboard/cesium"},
    gzip: false
  )

  plug(Plug.Session,
    store: :cookie,
    key: "_elixir_tak_key",
    signing_salt: "tak_dashboard"
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(ElixirTAKWeb.Router)
end
