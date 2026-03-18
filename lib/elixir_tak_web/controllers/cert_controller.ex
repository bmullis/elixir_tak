defmodule ElixirTAKWeb.CertController do
  @moduledoc "API endpoints for client certificate and connection profile management."

  use Phoenix.Controller, formats: [:json]

  alias ElixirTAK.CertManager

  @doc "POST /api/admin/certs/client - generate a new client certificate"
  def create(conn, %{"cn" => cn}) when is_binary(cn) and cn != "" do
    case CertManager.generate_client_cert(cn: cn) do
      {:ok, info} ->
        conn
        |> put_status(:created)
        |> json(%{
          cn: info.cn,
          serial: format_serial(info.serial),
          fingerprint: info.fingerprint,
          created_at: info.created_at
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "cn is required"})
  end

  @doc "GET /api/admin/certs - list all client certificates"
  def index(conn, _params) do
    {:ok, certs} = CertManager.list_certs()

    json(conn, %{
      certs:
        Enum.map(certs, fn c ->
          %{
            cn: c.cn,
            serial: format_serial(c.serial),
            fingerprint: c.fingerprint,
            status: c.status
          }
        end)
    })
  end

  @doc "POST /api/admin/certs/:serial/revoke - revoke a client certificate"
  def revoke(conn, %{"serial" => serial_str}) do
    case parse_serial(serial_str) do
      {:ok, serial} ->
        CertManager.revoke_cert(serial)
        json(conn, %{status: "revoked", serial: serial_str})

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid serial number"})
    end
  end

  @doc "GET /api/admin/certs/profile - download a connection profile zip"
  def profile(conn, %{"cn" => cn} = params) when is_binary(cn) and cn != "" do
    host = Map.get(params, "host") || request_host(conn)
    port = parse_port(Map.get(params, "port", "8089"))

    case CertManager.generate_profile(cn: cn, host: host, port: port) do
      {:ok, zip_binary} ->
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{cn}-profile.zip\"")
        |> send_resp(200, zip_binary)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  def profile(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "cn is required"})
  end

  # -- Helpers ---------------------------------------------------------------

  defp format_serial(serial) when is_integer(serial) do
    Integer.to_string(serial, 16) |> String.pad_leading(2, "0")
  end

  defp parse_serial(str) do
    case Integer.parse(str, 16) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_port(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 and n < 65536 -> n
      _ -> 8089
    end
  end

  defp parse_port(n) when is_integer(n), do: n
  defp parse_port(_), do: 8089

  defp request_host(conn) do
    conn.host || "localhost"
  end
end
