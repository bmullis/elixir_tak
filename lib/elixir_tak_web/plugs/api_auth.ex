defmodule ElixirTAKWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug that authenticates API requests via Bearer token.

  Extracts the token from the `Authorization: Bearer <token>` header,
  validates it against the TokenStore, and assigns `:api_token` and
  `:api_role` to the connection.

  When no tokens exist in the store, all requests are allowed through
  as "admin" to allow initial setup (bootstrap mode).
  """

  import Plug.Conn

  alias ElixirTAK.Auth.TokenStore

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if bootstrap_mode?() do
      conn
      |> assign(:api_token, nil)
      |> assign(:api_role, "admin")
    else
      case get_bearer_token(conn) do
        nil ->
          unauthorized(conn)

        raw_token ->
          case TokenStore.lookup(raw_token) do
            {:ok, token} ->
              TokenStore.touch(token.token_hash)

              conn
              |> assign(:api_token, token)
              |> assign(:api_role, token.role)

            :not_found ->
              unauthorized(conn)
          end
      end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "Invalid or missing API token"}))
    |> halt()
  end

  defp bootstrap_mode? do
    TokenStore.count() == 0
  end
end
