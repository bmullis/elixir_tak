defmodule ElixirTAK.History.Queries do
  @moduledoc "Query functions for the persisted event history."

  import Ecto.Query

  alias ElixirTAK.History.EventRecord
  alias ElixirTAK.Repo

  @default_limit 100

  @doc "Events by UID, newest first."
  def by_uid(uid, opts \\ []) do
    EventRecord
    |> where([e], e.uid == ^uid)
    |> apply_filters(opts)
    |> order_by([e], desc: e.event_time)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc "Events in a time range."
  def by_time_range(start_dt, end_dt, opts \\ []) do
    EventRecord
    |> where([e], e.event_time >= ^start_dt and e.event_time <= ^end_dt)
    |> apply_filters(opts)
    |> order_by([e], desc: e.event_time)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc "Events by type prefix (e.g. `\"a-f-\"` for all friendly)."
  def by_type(type_prefix, opts \\ []) do
    pattern = type_prefix <> "%"

    EventRecord
    |> where([e], like(e.type, ^pattern))
    |> apply_filters(opts)
    |> order_by([e], desc: e.event_time)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc "Events within a geo bounding box."
  def by_bbox(min_lat, max_lat, min_lon, max_lon, opts \\ []) do
    EventRecord
    |> where([e], e.lat >= ^min_lat and e.lat <= ^max_lat)
    |> where([e], e.lon >= ^min_lon and e.lon <= ^max_lon)
    |> apply_filters(opts)
    |> order_by([e], desc: e.event_time)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc "Track history for a UID - returns points in time order (oldest first)."
  def track(uid, opts \\ []) do
    EventRecord
    |> where([e], e.uid == ^uid)
    |> where([e], not is_nil(e.lat) and not is_nil(e.lon))
    |> apply_time_bounds(opts)
    |> order_by([e], asc: e.event_time)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc "Most recent event per UID (like SACache but from disk)."
  def latest_per_uid(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    # Subquery: max event_time per uid
    sub =
      from(e in EventRecord,
        group_by: e.uid,
        select: %{uid: e.uid, max_time: max(e.event_time)}
      )

    from(e in EventRecord,
      join: s in subquery(sub),
      on: e.uid == s.uid and e.event_time == s.max_time,
      limit: ^limit
    )
    |> Repo.all()
  end

  # -- Private filters -------------------------------------------------------

  defp apply_filters(query, opts) do
    query
    |> apply_time_bounds(opts)
    |> maybe_filter_type(opts)
    |> maybe_filter_group(opts)
  end

  defp apply_time_bounds(query, opts) do
    query
    |> then(fn q ->
      case Keyword.get(opts, :since) do
        nil -> q
        dt -> where(q, [e], e.event_time >= ^dt)
      end
    end)
    |> then(fn q ->
      case Keyword.get(opts, :until) do
        nil -> q
        dt -> where(q, [e], e.event_time <= ^dt)
      end
    end)
  end

  defp maybe_filter_type(query, opts) do
    case Keyword.get(opts, :type) do
      nil -> query
      prefix -> where(query, [e], like(e.type, ^(prefix <> "%")))
    end
  end

  defp maybe_filter_group(query, opts) do
    case Keyword.get(opts, :group) do
      nil -> query
      group -> where(query, [e], e.group_name == ^group)
    end
  end

  defp apply_pagination(query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end
end
