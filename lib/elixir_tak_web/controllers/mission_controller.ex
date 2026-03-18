defmodule ElixirTAKWeb.MissionController do
  @moduledoc "REST API for TAK-compatible mission management."

  use Phoenix.Controller, formats: [:json]

  alias ElixirTAK.Missions.MissionStore
  alias ElixirTAK.Auth.AuditLog

  plug(
    ElixirTAKWeb.Plugs.RequireRole,
    "operator" when action in [:create, :update, :add_contents, :subscribe]
  )

  plug(ElixirTAKWeb.Plugs.RequireRole, "admin" when action in [:delete])

  @doc "POST /api/missions - create a mission"
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      creator_uid: params["creator_uid"],
      group_name: params["group_name"]
    }

    case MissionStore.create(attrs) do
      {:ok, mission} ->
        AuditLog.record("mission.create", conn, "mission", mission.name)

        conn
        |> put_status(:created)
        |> json(serialize_mission(mission))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_errors(changeset)})
    end
  end

  @doc "GET /api/missions - list all missions"
  def index(conn, _params) do
    missions = MissionStore.list()

    json(conn, %{
      count: length(missions),
      missions: Enum.map(missions, &serialize_mission/1)
    })
  end

  @doc "GET /api/missions/:name - mission details with contents"
  def show(conn, %{"name" => name}) do
    case MissionStore.get(name) do
      {:ok, mission} ->
        json(conn, serialize_mission(mission))

      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Mission not found", name: name})
    end
  end

  @doc "PUT /api/missions/:name/contents - add content to a mission"
  def add_contents(conn, %{"name" => name} = params) do
    attrs = %{
      content_type: params["content_type"],
      content_uid: params["content_uid"],
      data_package_hash: params["data_package_hash"],
      metadata: if(params["metadata"], do: Jason.encode!(params["metadata"]))
    }

    case MissionStore.add_content(name, attrs) do
      {:ok, mission} ->
        AuditLog.record("mission.add_content", conn, "mission", name, %{
          content_type: attrs.content_type,
          content_uid: attrs.content_uid
        })

        json(conn, serialize_mission(mission))

      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Mission not found", name: name})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_errors(changeset)})
    end
  end

  @doc "DELETE /api/missions/:name - delete a mission"
  def delete(conn, %{"name" => name}) do
    case MissionStore.delete(name) do
      :ok ->
        AuditLog.record("mission.delete", conn, "mission", name)
        json(conn, %{status: "ok", message: "Mission '#{name}' deleted"})

      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Mission not found", name: name})
    end
  end

  @doc "POST /api/missions/:name/subscription - subscribe a client"
  def subscribe(conn, %{"name" => name} = params) do
    client_uid = params["client_uid"]

    if is_nil(client_uid) or client_uid == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "client_uid is required"})
    else
      case MissionStore.subscribe(name, client_uid) do
        {:ok, mission} ->
          AuditLog.record("mission.subscribe", conn, "mission", name, %{client_uid: client_uid})
          json(conn, serialize_mission(mission))

        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Mission not found", name: name})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Subscription failed", details: format_errors(changeset)})
      end
    end
  end

  # -- Private ---------------------------------------------------------------

  defp serialize_mission(mission) do
    %{
      id: mission.id,
      name: mission.name,
      description: mission.description,
      creator_uid: mission.creator_uid,
      group_name: mission.group_name,
      created_at: mission.inserted_at && DateTime.to_iso8601(mission.inserted_at),
      updated_at: mission.updated_at && DateTime.to_iso8601(mission.updated_at),
      contents: serialize_contents(mission),
      subscriptions: serialize_subscriptions(mission)
    }
  end

  defp serialize_contents(%{contents: %Ecto.Association.NotLoaded{}}), do: []

  defp serialize_contents(%{contents: contents}) do
    Enum.map(contents, fn c ->
      %{
        id: c.id,
        content_type: c.content_type,
        content_uid: c.content_uid,
        data_package_hash: c.data_package_hash,
        metadata: if(c.metadata, do: Jason.decode!(c.metadata)),
        added_at: c.inserted_at && DateTime.to_iso8601(c.inserted_at)
      }
    end)
  end

  defp serialize_subscriptions(%{subscriptions: %Ecto.Association.NotLoaded{}}), do: []

  defp serialize_subscriptions(%{subscriptions: subs}) do
    Enum.map(subs, fn s ->
      %{
        client_uid: s.client_uid,
        subscribed_at: s.inserted_at && DateTime.to_iso8601(s.inserted_at)
      }
    end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
