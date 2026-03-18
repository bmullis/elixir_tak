defmodule ElixirTAKWeb.DataPackageController do
  use Phoenix.Controller, formats: [:json]

  alias ElixirTAK.DataPackages

  @doc "POST /Marti/sync/missionupload - multipart file upload"
  def upload(conn, params) do
    with %Plug.Upload{path: path, filename: filename} <- params["assetfile"],
         {:ok, content} <- File.read(path) do
      metadata = %{
        creator_uid: params["creatorUid"],
        tool: params["tool"] || "public",
        keywords: parse_keywords(params["keywords"]),
        mime_type: MIME.from_path(filename)
      }

      {:ok, hash} = DataPackages.store(filename, content, metadata)
      json(conn, %{hash: hash, filename: filename, size: byte_size(content)})
    else
      nil -> conn |> put_status(400) |> json(%{error: "missing assetfile"})
      {:error, reason} -> conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  @doc "GET /Marti/sync/missionquery - list packages"
  def query(conn, params) do
    packages =
      case params["tool"] do
        nil -> DataPackages.list()
        tool -> DataPackages.list_by_tool(tool)
      end

    json(conn, %{resultCount: length(packages), results: format_packages(packages)})
  end

  @doc "GET /Marti/sync/content - download by hash"
  def download(conn, params) do
    case DataPackages.get(params["hash"]) do
      {:ok, entry, content} ->
        conn
        |> put_resp_content_type(entry.mime_type)
        |> put_resp_header("content-disposition", "attachment; filename=\"#{entry.filename}\"")
        |> send_resp(200, content)

      :not_found ->
        conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  @doc "GET /Marti/api/sync/metadata/:hash/tool - metadata lookup"
  def metadata(conn, %{"hash" => hash}) do
    case DataPackages.get_metadata(hash) do
      {:ok, entry} -> json(conn, format_package(entry))
      :not_found -> conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  defp parse_keywords(nil), do: []
  defp parse_keywords(kw) when is_binary(kw), do: String.split(kw, ",", trim: true)
  defp parse_keywords(kw) when is_list(kw), do: kw

  defp format_packages(packages), do: Enum.map(packages, &format_package/1)

  defp format_package(entry) do
    %{
      Hash: entry.hash,
      Name: entry.filename,
      MIMEType: entry.mime_type,
      Size: entry.size,
      Tool: entry.tool,
      CreatorUid: entry.creator_uid,
      SubmissionDateTime: DateTime.to_iso8601(entry.upload_time),
      Keywords: entry.keywords
    }
  end
end
