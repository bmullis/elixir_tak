defmodule ElixirTAK.Federation.ServerID do
  @moduledoc """
  Manages a persistent, unique server identity for federation.

  The server UID is stored on disk at `data/server_uid` and cached in
  `:persistent_term` for fast access. If no file exists on first call,
  a new UID is generated and persisted.
  """

  @persistent_term_key :elixir_tak_server_uid
  @uid_file "data/server_uid"

  @doc """
  Returns the server UID, reading from `:persistent_term` cache.

  On the first call, loads from disk (or generates a new UID) and caches it.
  """
  @spec get() :: String.t()
  def get do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil -> get_or_create()
      uid -> uid
    end
  end

  @doc """
  Reads the server UID from disk, or generates and persists a new one.

  The result is cached in `:persistent_term` for subsequent fast access.
  Returns the server UID string.
  """
  @spec get_or_create() :: String.t()
  def get_or_create do
    uid =
      case File.read(@uid_file) do
        {:ok, contents} ->
          contents |> String.trim()

        {:error, _} ->
          generate_uid()
      end

    :persistent_term.put(@persistent_term_key, uid)
    uid
  end

  defp generate_uid do
    uid = "ELIXIRTAK-#{Base.encode16(:crypto.strong_rand_bytes(8))}"
    File.mkdir_p!(Path.dirname(@uid_file))
    File.write!(@uid_file, uid)
    uid
  end
end
