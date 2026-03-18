defmodule ElixirTAK.Missions.MissionStore do
  @moduledoc """
  ETS + SQLite store for missions.

  Keeps missions cached in ETS for fast reads. All mutations persist to
  SQLite and update ETS. Contents and subscriptions are loaded eagerly
  with the mission.
  """

  use GenServer

  alias ElixirTAK.Repo
  alias ElixirTAK.Missions.{Mission, MissionContent, MissionSubscription}

  import Ecto.Query

  @table :mission_cache

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Create a new mission. Returns `{:ok, mission}` or `{:error, changeset}`."
  def create(attrs) do
    case %Mission{} |> Mission.changeset(attrs) |> Repo.insert() do
      {:ok, mission} ->
        mission = Repo.preload(mission, [:contents, :subscriptions])
        :ets.insert(@table, {mission.name, mission})
        {:ok, mission}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Get a mission by name. Returns `{:ok, mission}` or `:not_found`."
  def get(name) do
    case :ets.lookup(@table, name) do
      [{^name, mission}] -> {:ok, mission}
      [] -> :not_found
    end
  end

  @doc "List all missions."
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_name, mission} -> mission end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc "Delete a mission by name."
  def delete(name) do
    case get(name) do
      {:ok, mission} ->
        Repo.delete(mission)
        :ets.delete(@table, name)
        :ok

      :not_found ->
        :not_found
    end
  end

  @doc "Add content to a mission."
  def add_content(mission_name, attrs) do
    case get(mission_name) do
      {:ok, mission} ->
        content_attrs = Map.put(attrs, :mission_id, mission.id)

        case %MissionContent{} |> MissionContent.changeset(content_attrs) |> Repo.insert() do
          {:ok, _content} ->
            reload_mission(mission.name)

          {:error, changeset} ->
            {:error, changeset}
        end

      :not_found ->
        :not_found
    end
  end

  @doc "Remove content from a mission."
  def remove_content(mission_name, content_uid) do
    case get(mission_name) do
      {:ok, mission} ->
        from(c in MissionContent,
          where: c.mission_id == ^mission.id and c.content_uid == ^content_uid
        )
        |> Repo.delete_all()

        reload_mission(mission.name)

      :not_found ->
        :not_found
    end
  end

  @doc "Subscribe a client to a mission."
  def subscribe(mission_name, client_uid) do
    case get(mission_name) do
      {:ok, mission} ->
        attrs = %{mission_id: mission.id, client_uid: client_uid}

        case %MissionSubscription{} |> MissionSubscription.changeset(attrs) |> Repo.insert() do
          {:ok, _sub} ->
            reload_mission(mission.name)

          {:error, changeset} ->
            {:error, changeset}
        end

      :not_found ->
        :not_found
    end
  end

  @doc "Unsubscribe a client from a mission."
  def unsubscribe(mission_name, client_uid) do
    case get(mission_name) do
      {:ok, mission} ->
        from(s in MissionSubscription,
          where: s.mission_id == ^mission.id and s.client_uid == ^client_uid
        )
        |> Repo.delete_all()

        reload_mission(mission.name)

      :not_found ->
        :not_found
    end
  end

  @doc "Get count of missions."
  def count do
    :ets.info(@table, :size)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    load_from_db()
    {:ok, %{}}
  end

  # -- Private ---------------------------------------------------------------

  defp load_from_db do
    from(m in Mission, preload: [:contents, :subscriptions])
    |> Repo.all()
    |> Enum.each(fn mission ->
      :ets.insert(@table, {mission.name, mission})
    end)
  end

  defp reload_mission(name) do
    case Repo.one(
           from(m in Mission, where: m.name == ^name, preload: [:contents, :subscriptions])
         ) do
      nil ->
        :ets.delete(@table, name)
        :not_found

      mission ->
        :ets.insert(@table, {name, mission})
        {:ok, mission}
    end
  end
end
