defmodule ElixirTAK.DataPackages do
  @moduledoc """
  Manages data package metadata (ETS) and file storage (disk).

  Files are stored at `data/packages/<hash>/<filename>` where hash is the
  SHA-256 hex digest of the file content. ATAK references packages by hash.
  """

  use GenServer

  @table :data_packages
  @storage_dir Application.compile_env(:elixir_tak, :data_packages_dir, "data/packages")

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store a data package. Returns `{:ok, hash}` on success."
  def store(filename, content, metadata \\ %{}) do
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    dir = Path.join(@storage_dir, hash)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, filename), content)

    entry = %{
      hash: hash,
      filename: filename,
      mime_type: Map.get(metadata, :mime_type, "application/octet-stream"),
      size: byte_size(content),
      tool: Map.get(metadata, :tool, "public"),
      creator_uid: Map.get(metadata, :creator_uid),
      upload_time: DateTime.utc_now(),
      keywords: Map.get(metadata, :keywords, [])
    }

    :ets.insert(@table, {hash, entry})
    {:ok, hash}
  end

  @doc "Get a package by hash. Returns `{:ok, metadata, content}` or `:not_found`."
  def get(hash) do
    case :ets.lookup(@table, hash) do
      [{^hash, entry}] ->
        path = Path.join([@storage_dir, hash, entry.filename])

        case File.read(path) do
          {:ok, content} -> {:ok, entry, content}
          {:error, _} -> :not_found
        end

      [] ->
        :not_found
    end
  end

  @doc "Get metadata only for a package. Returns `{:ok, metadata}` or `:not_found`."
  def get_metadata(hash) do
    case :ets.lookup(@table, hash) do
      [{^hash, entry}] -> {:ok, entry}
      [] -> :not_found
    end
  end

  @doc "List all package metadata."
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_hash, entry} -> entry end)
  end

  @doc "List packages filtered by tool name."
  def list_by_tool(tool) do
    list() |> Enum.filter(&(&1.tool == tool))
  end

  @doc "Delete a package by hash."
  def delete(hash) do
    case :ets.lookup(@table, hash) do
      [{^hash, entry}] ->
        path = Path.join([@storage_dir, hash, entry.filename])
        File.rm(path)
        File.rmdir(Path.join(@storage_dir, hash))
        :ets.delete(@table, hash)
        :ok

      [] ->
        :not_found
    end
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    File.mkdir_p!(@storage_dir)
    {:ok, []}
  end
end
