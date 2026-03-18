defmodule ElixirTAKWeb.DataPackageControllerTest do
  use ElixirTAKWeb.ConnCase

  @test_content "hello world data package"

  setup do
    # Use a temp directory for test data packages
    on_exit(fn ->
      # Clean up any packages created during tests
      for entry <- ElixirTAK.DataPackages.list() do
        ElixirTAK.DataPackages.delete(entry.hash)
      end
    end)

    :ok
  end

  describe "POST /Marti/sync/missionupload" do
    test "uploads a file and returns hash", %{conn: conn} do
      upload = %Plug.Upload{
        path: write_temp_file(@test_content),
        filename: "test.zip",
        content_type: "application/zip"
      }

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/Marti/sync/missionupload", %{
          "assetfile" => upload,
          "creatorUid" => "test-uid",
          "keywords" => "tag1,tag2"
        })

      body = json_response(conn, 200)
      assert is_binary(body["hash"])
      assert body["filename"] == "test.zip"
      assert body["size"] == byte_size(@test_content)
    end

    test "returns 400 when assetfile is missing", %{conn: conn} do
      conn = post(conn, "/Marti/sync/missionupload", %{})
      assert json_response(conn, 400)["error"] == "missing assetfile"
    end
  end

  describe "GET /Marti/sync/content" do
    test "downloads a previously uploaded file", %{conn: conn} do
      {:ok, hash} = ElixirTAK.DataPackages.store("test.bin", @test_content)

      conn = get(conn, "/Marti/sync/content", %{"hash" => hash})
      assert conn.status == 200
      assert conn.resp_body == @test_content
    end

    test "returns 404 for nonexistent hash", %{conn: conn} do
      conn = get(conn, "/Marti/sync/content", %{"hash" => "deadbeef"})
      assert json_response(conn, 404)["error"] == "not found"
    end
  end

  describe "GET /Marti/sync/missionquery" do
    test "lists uploaded packages", %{conn: conn} do
      {:ok, _hash} = ElixirTAK.DataPackages.store("a.zip", "aaa", %{tool: "public"})
      {:ok, _hash} = ElixirTAK.DataPackages.store("b.zip", "bbb", %{tool: "private"})

      conn = get(conn, "/Marti/sync/missionquery")
      body = json_response(conn, 200)
      assert body["resultCount"] == 2
    end

    test "filters by tool", %{conn: conn} do
      {:ok, _hash} = ElixirTAK.DataPackages.store("a.zip", "aaa", %{tool: "public"})
      {:ok, _hash} = ElixirTAK.DataPackages.store("b.zip", "bbb", %{tool: "private"})

      conn = get(conn, "/Marti/sync/missionquery", %{"tool" => "public"})
      body = json_response(conn, 200)
      assert body["resultCount"] == 1
      assert hd(body["results"])["Tool"] == "public"
    end
  end

  describe "GET /Marti/api/sync/metadata/:hash/tool" do
    test "returns metadata for a package", %{conn: conn} do
      {:ok, hash} = ElixirTAK.DataPackages.store("meta.zip", "metadata test")

      conn = get(conn, "/Marti/api/sync/metadata/#{hash}/tool")
      body = json_response(conn, 200)
      assert body["Hash"] == hash
      assert body["Name"] == "meta.zip"
    end

    test "returns 404 for nonexistent hash", %{conn: conn} do
      conn = get(conn, "/Marti/api/sync/metadata/deadbeef/tool")
      assert json_response(conn, 404)["error"] == "not found"
    end
  end

  defp write_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "elixir_tak_test_#{:rand.uniform(100_000)}")
    File.write!(path, content)
    path
  end
end
