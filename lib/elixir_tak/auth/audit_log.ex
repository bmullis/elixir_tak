defmodule ElixirTAK.Auth.AuditLog do
  @moduledoc """
  Records admin actions to SQLite for audit trail.

  Writes are async (cast) to avoid blocking request handling.
  """

  use GenServer

  alias ElixirTAK.Repo

  import Ecto.Query

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_log" do
    field(:action, :string)
    field(:actor, :string)
    field(:role, :string)
    field(:resource_type, :string)
    field(:resource_id, :string)
    field(:details, :string)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Record an audit event (async)."
  def record(action, conn_or_attrs \\ %{}) do
    attrs =
      case conn_or_attrs do
        %Plug.Conn{} = conn ->
          token = conn.assigns[:api_token]

          %{
            actor: if(token, do: token.name, else: "anonymous"),
            role: conn.assigns[:api_role] || "unknown"
          }

        map when is_map(map) ->
          map
      end

    do_cast(action, attrs)
  end

  @doc "Record an audit event with resource info (async)."
  def record(action, conn, resource_type, resource_id, details \\ nil) do
    token = conn.assigns[:api_token]

    attrs = %{
      actor: if(token, do: token.name, else: "anonymous"),
      role: conn.assigns[:api_role] || "unknown",
      resource_type: resource_type,
      resource_id: resource_id,
      details: if(details, do: Jason.encode!(details))
    }

    do_cast(action, attrs)
  end

  defp do_cast(action, attrs) do
    if Application.get_env(:elixir_tak, :env) != :test do
      GenServer.cast(__MODULE__, {:record, action, attrs})
    end
  end

  @doc "Query recent audit log entries."
  def recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(a in __MODULE__,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> maybe_filter_action(opts[:action])
    |> maybe_filter_actor(opts[:actor])
    |> Repo.all()
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record, action, attrs}, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    try do
      Repo.insert_all("audit_log", [
        %{
          id: Ecto.UUID.generate(),
          action: action,
          actor: attrs[:actor],
          role: attrs[:role],
          resource_type: attrs[:resource_type],
          resource_id: attrs[:resource_id],
          details: attrs[:details],
          inserted_at: now
        }
      ])
    rescue
      _ -> :ok
    end

    {:noreply, state}
  end

  # -- Private ---------------------------------------------------------------

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, action), do: where(query, [a], a.action == ^action)

  defp maybe_filter_actor(query, nil), do: query
  defp maybe_filter_actor(query, actor), do: where(query, [a], a.actor == ^actor)
end
