defmodule ElixirTAKWeb.Router do
  use ElixirTAKWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:put_root_layout, html: {ElixirTAKWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :marti do
    plug(:accepts, ["json", "xml"])
  end

  pipeline :api_auth do
    plug(:accepts, ["json"])
    plug(ElixirTAKWeb.Plugs.ApiAuth)
    plug(ElixirTAKWeb.Plugs.RateLimiter)
  end

  # Dashboard REST API
  scope "/api/dashboard", ElixirTAKWeb do
    pipe_through(:api)

    get("/snapshot", DashboardApiController, :snapshot)
  end

  # React dashboard — catch-all serves index.html, client-side routing takes over
  scope "/dashboard", ElixirTAKWeb do
    pipe_through(:browser)

    get("/", DashboardController, :index)
    get("/*path", DashboardController, :index)
  end

  # TAK client data package API — matches ATAK's expected endpoints
  scope "/Marti", ElixirTAKWeb do
    pipe_through(:marti)

    post("/sync/missionupload", DataPackageController, :upload)
    get("/sync/missionquery", DataPackageController, :query)
    get("/sync/content", DataPackageController, :download)
    get("/api/sync/metadata/:hash/tool", DataPackageController, :metadata)
    get("/vcm", VideoController, :vcm)
    get("/api/video", VideoController, :marti_video_list)
    get("/api/video/:uid/hls/:filename", VideoController, :hls)
    post("/api/video/:uid/snapshot", VideoController, :snapshot)
    get("/api/video/:uid/snapshot/latest", VideoController, :latest_snapshot)
  end

  # Mission API (authenticated)
  scope "/api/missions", ElixirTAKWeb do
    pipe_through(:api_auth)

    get("/", MissionController, :index)
    post("/", MissionController, :create)
    get("/:name", MissionController, :show)
    put("/:name/contents", MissionController, :add_contents)
    delete("/:name", MissionController, :delete)
    post("/:name/subscription", MissionController, :subscribe)
  end

  # Admin/integrator API (authenticated)
  scope "/api/admin", ElixirTAKWeb do
    pipe_through(:api_auth)

    get("/health", AdminController, :health)
    get("/clients", AdminController, :list_clients)
    delete("/clients/:uid", AdminController, :disconnect_client)
    get("/groups", AdminController, :list_groups)
    post("/groups/:name/announce", AdminController, :announce)
    get("/config", AdminController, :get_config)
    put("/config", AdminController, :update_config)
    get("/track/:uid", AdminController, :track)
    get("/federation/peers", AdminController, :list_federation_peers)
    post("/federation/peers", AdminController, :manage_federation_peer)

    # Token management
    get("/tokens", TokenController, :index)
    post("/tokens", TokenController, :create)
    delete("/tokens/:id", TokenController, :revoke)

    # Audit log
    get("/audit", TokenController, :audit_log)

    # Certificate management
    post("/certs/client", CertController, :create)
    get("/certs", CertController, :index)
    post("/certs/:serial/revoke", CertController, :revoke)
    get("/certs/profile", CertController, :profile)
  end

  # Video stream management API
  scope "/api/video", ElixirTAKWeb do
    pipe_through(:api)

    get("/", VideoController, :index)
    get("/:uid", VideoController, :show)
    post("/", VideoController, :create)
    put("/:uid", VideoController, :update)
    delete("/:uid", VideoController, :delete)
  end
end
