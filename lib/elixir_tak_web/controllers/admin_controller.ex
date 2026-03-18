defmodule ElixirTAKWeb.AdminController do
  @moduledoc "Admin/integrator REST API for server management."

  use Phoenix.Controller, formats: [:json]

  alias ElixirTAK.ClientRegistry
  alias ElixirTAK.Protocol.CotEvent

  @pubsub ElixirTAK.PubSub
  @cot_topic "cot:broadcast"

  # -- Existing endpoints ----------------------------------------------------

  @doc "GET /api/admin/health - server health info"
  def health(conn, _params) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    sa_count =
      try do
        :ets.info(:sa_cache, :size) || 0
      rescue
        _ -> 0
      end

    dp_count =
      try do
        :ets.info(:data_packages, :size) || 0
      rescue
        _ -> 0
      end

    memory = :erlang.memory()

    json(conn, %{
      status: "ok",
      uptime_seconds: div(uptime_ms, 1000),
      connected_clients: sa_count,
      data_packages: dp_count,
      memory: %{
        total: memory[:total],
        processes: memory[:processes],
        ets: memory[:ets]
      }
    })
  end

  @doc "GET /api/admin/clients - list connected clients with metadata"
  def list_clients(conn, _params) do
    clients =
      ClientRegistry.get_all()
      |> Enum.map(fn client ->
        %{
          uid: client.uid,
          callsign: client[:callsign],
          group: client[:group],
          peer: format_peer(client[:peer]),
          cert_cn: client[:cert_cn],
          connected_at: client[:connected_at] && DateTime.to_iso8601(client.connected_at)
        }
      end)

    json(conn, %{count: length(clients), clients: clients})
  end

  @doc "DELETE /api/admin/clients/:uid - force-disconnect a client"
  def disconnect_client(conn, %{"uid" => uid}) do
    case ClientRegistry.lookup_pid(uid) do
      {:ok, pid} ->
        send(pid, :admin_disconnect)
        json(conn, %{status: "ok", message: "Disconnect signal sent to #{uid}"})

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Client not found", uid: uid})
    end
  end

  @doc "GET /api/admin/track/:uid - track history for a UID"
  def track(conn, %{"uid" => uid} = params) do
    opts =
      []
      |> maybe_add_time(:since, params["since"])
      |> maybe_add_time(:until, params["until"])
      |> Keyword.put(:limit, parse_int(params["limit"], 500))

    points =
      ElixirTAK.History.Queries.track(uid, opts)
      |> Enum.map(fn record ->
        %{
          lat: record.lat,
          lon: record.lon,
          hae: record.hae,
          speed: record.speed,
          course: record.course,
          time: record.event_time && DateTime.to_iso8601(record.event_time)
        }
      end)

    json(conn, %{uid: uid, count: length(points), points: points})
  end

  # -- Groups ----------------------------------------------------------------

  @doc "GET /api/admin/groups - list active groups with member counts"
  def list_groups(conn, _params) do
    groups =
      ClientRegistry.get_all()
      |> Enum.group_by(fn client -> client[:group] || "(ungrouped)" end)
      |> Enum.map(fn {group, members} ->
        %{
          name: group,
          member_count: length(members),
          members:
            Enum.map(members, fn m ->
              %{uid: m.uid, callsign: m[:callsign]}
            end)
        }
      end)
      |> Enum.sort_by(& &1.name)

    json(conn, %{count: length(groups), groups: groups})
  end

  @doc "POST /api/admin/groups/:name/announce - broadcast an announcement to a group"
  def announce(conn, %{"name" => group_name} = params) do
    message = params["message"]

    if is_nil(message) or message == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "message is required"})
    else
      now = DateTime.utc_now()
      server_uid = "ElixirTAK-Admin-#{:erlang.unique_integer([:positive])}"
      callsign = Application.get_env(:elixir_tak, :dashboard_callsign, "ElixirTAK-Admin")
      stale = DateTime.add(now, 300, :second)

      event = %CotEvent{
        uid: server_uid,
        type: "b-t-f",
        how: "h-g-i-g-o",
        time: now,
        start: now,
        stale: stale,
        point: %{lat: 0.0, lon: 0.0, hae: 0.0, ce: 9_999_999.0, le: 9_999_999.0},
        detail: %{callsign: callsign},
        raw_detail:
          "<detail>" <>
            "<__chat chatroom=\"#{xml_escape(group_name)}\" groupOwner=\"false\" " <>
            "id=\"#{server_uid}\" senderCallsign=\"#{xml_escape(callsign)}\">" <>
            "<chatgrp uid0=\"#{server_uid}\" uid1=\"All Chat Rooms\" id=\"#{xml_escape(group_name)}\"/>" <>
            "</__chat>" <>
            "<remarks source=\"#{xml_escape(callsign)}\" " <>
            "time=\"#{DateTime.to_iso8601(now)}\">" <>
            xml_escape(message) <>
            "</remarks>" <>
            "</detail>"
      }

      Phoenix.PubSub.broadcast(
        @pubsub,
        @cot_topic,
        {:cot_broadcast, server_uid, event, group_name}
      )

      ElixirTAK.ChatCache.put(event)

      json(conn, %{status: "ok", message: "Announcement broadcast to group #{group_name}"})
    end
  end

  # -- Config ----------------------------------------------------------------

  @doc "GET /api/admin/config - server configuration (read-only)"
  def get_config(conn, _params) do
    fed_config = Application.get_env(:elixir_tak, ElixirTAK.Federation, [])
    retention_config = Application.get_env(:elixir_tak, ElixirTAK.History.Retention, [])

    config = %{
      tcp_port: Application.get_env(:elixir_tak, :tcp_port, 8087),
      tls_port: Application.get_env(:elixir_tak, :tls_port, 8089),
      tls_enabled: Application.get_env(:elixir_tak, :tls_enabled, false),
      simulator: Application.get_env(:elixir_tak, :simulator, false),
      dashboard_callsign: Application.get_env(:elixir_tak, :dashboard_callsign, "ElixirTAK-COP"),
      dashboard_group: Application.get_env(:elixir_tak, :dashboard_group, "Cyan"),
      federation: %{
        enabled: Keyword.get(fed_config, :enabled, false),
        transport: Keyword.get(fed_config, :transport, :beam),
        server_name: Keyword.get(fed_config, :server_name, "ElixirTAK")
      },
      retention: %{
        max_age_hours: Keyword.get(retention_config, :max_age_hours, 168),
        cleanup_interval_minutes: Keyword.get(retention_config, :cleanup_interval_minutes, 60)
      }
    }

    json(conn, config)
  end

  @doc "PUT /api/admin/config - update runtime configuration"
  def update_config(conn, params) do
    updated = []

    updated =
      if Map.has_key?(params, "simulator") do
        val = params["simulator"] == true
        Application.put_env(:elixir_tak, :simulator, val)
        ["simulator=#{val}" | updated]
      else
        updated
      end

    updated =
      if Map.has_key?(params, "dashboard_callsign") do
        val = params["dashboard_callsign"]
        Application.put_env(:elixir_tak, :dashboard_callsign, val)
        ["dashboard_callsign=#{val}" | updated]
      else
        updated
      end

    updated =
      if Map.has_key?(params, "dashboard_group") do
        val = params["dashboard_group"]
        Application.put_env(:elixir_tak, :dashboard_group, val)
        ["dashboard_group=#{val}" | updated]
      else
        updated
      end

    updated =
      if Map.has_key?(params, "retention") do
        retention = params["retention"]
        current = Application.get_env(:elixir_tak, ElixirTAK.History.Retention, [])

        current =
          if is_integer(retention["max_age_hours"]) do
            Keyword.put(current, :max_age_hours, retention["max_age_hours"])
          else
            current
          end

        current =
          if is_integer(retention["cleanup_interval_minutes"]) do
            Keyword.put(current, :cleanup_interval_minutes, retention["cleanup_interval_minutes"])
          else
            current
          end

        Application.put_env(:elixir_tak, ElixirTAK.History.Retention, current)
        ["retention" | updated]
      else
        updated
      end

    if updated == [] do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No recognized configuration keys provided"})
    else
      json(conn, %{status: "ok", updated: Enum.reverse(updated)})
    end
  end

  # -- Federation peers ------------------------------------------------------

  @doc "GET /api/admin/federation/peers - list federation peers and status"
  def list_federation_peers(conn, _params) do
    if federation_running?() do
      peers =
        ElixirTAK.Federation.Manager.list_peers()
        |> Enum.map(fn {peer_id, info} ->
          %{
            peer_id: to_string(peer_id),
            status: info.status,
            connected_at: info[:connected_at] && DateTime.to_iso8601(info.connected_at)
          }
        end)

      stats = ElixirTAK.Federation.Manager.get_stats()

      json(conn, %{
        enabled: true,
        server_uid: stats.server_uid,
        peers_configured: stats.peers_configured,
        peers_connected: stats.peers_connected,
        events_sent: stats.events_sent,
        events_received: stats.events_received,
        peers: peers
      })
    else
      json(conn, %{enabled: false, peers: []})
    end
  end

  @doc "POST /api/admin/federation/peers - add or remove a federation peer"
  def manage_federation_peer(conn, params) do
    if not federation_running?() do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Federation is not enabled"})
    else
      case params["action"] do
        "add" ->
          peer = parse_peer(params["peer"])

          if peer do
            ElixirTAK.Federation.Manager.add_peer(peer)
            json(conn, %{status: "ok", message: "Peer #{inspect(peer)} add requested"})
          else
            conn
            |> put_status(:bad_request)
            |> json(%{error: "peer is required (node name as string)"})
          end

        "remove" ->
          peer = parse_peer(params["peer"])

          if peer do
            ElixirTAK.Federation.Manager.remove_peer(peer)
            json(conn, %{status: "ok", message: "Peer #{inspect(peer)} removed"})
          else
            conn
            |> put_status(:bad_request)
            |> json(%{error: "peer is required (node name as string)"})
          end

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "action must be 'add' or 'remove'"})
      end
    end
  end

  # -- Private ---------------------------------------------------------------

  defp federation_running? do
    GenServer.whereis(ElixirTAK.Federation.Manager) != nil
  end

  defp format_peer({ip, port}) when is_tuple(ip) do
    "#{:inet.ntoa(ip)}:#{port}"
  end

  defp format_peer(_), do: nil

  defp parse_peer(name) when is_binary(name) and name != "" do
    String.to_atom(name)
  end

  defp parse_peer(_), do: nil

  defp xml_escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp maybe_add_time(opts, key, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> Keyword.put(opts, key, dt)
      _ -> opts
    end
  end

  defp maybe_add_time(opts, _key, _value), do: opts

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
end
