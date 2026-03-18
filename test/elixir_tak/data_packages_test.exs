defmodule ElixirTAK.DataPackagesTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.DataPackages

  setup do
    on_exit(fn ->
      for entry <- DataPackages.list() do
        DataPackages.delete(entry.hash)
      end
    end)

    :ok
  end

  test "store and retrieve a package" do
    {:ok, hash} = DataPackages.store("test.zip", "test content")
    assert is_binary(hash)
    assert String.length(hash) == 64

    {:ok, entry, content} = DataPackages.get(hash)
    assert content == "test content"
    assert entry.filename == "test.zip"
    assert entry.size == byte_size("test content")
  end

  test "hash is deterministic" do
    {:ok, hash1} = DataPackages.store("a.zip", "same content")
    DataPackages.delete(hash1)
    {:ok, hash2} = DataPackages.store("b.zip", "same content")
    assert hash1 == hash2
  end

  test "get returns :not_found for missing hash" do
    assert DataPackages.get("nonexistent") == :not_found
  end

  test "list returns all packages" do
    {:ok, _} = DataPackages.store("a.zip", "aaa")
    {:ok, _} = DataPackages.store("b.zip", "bbb")
    assert length(DataPackages.list()) == 2
  end

  test "list_by_tool filters correctly" do
    {:ok, _} = DataPackages.store("a.zip", "aaa", %{tool: "public"})
    {:ok, _} = DataPackages.store("b.zip", "bbb", %{tool: "private"})

    assert length(DataPackages.list_by_tool("public")) == 1
    assert length(DataPackages.list_by_tool("private")) == 1
    assert length(DataPackages.list_by_tool("other")) == 0
  end

  test "delete removes package" do
    {:ok, hash} = DataPackages.store("del.zip", "delete me")
    assert :ok = DataPackages.delete(hash)
    assert DataPackages.get(hash) == :not_found
  end

  test "delete returns :not_found for missing hash" do
    assert DataPackages.delete("nonexistent") == :not_found
  end

  test "store preserves metadata" do
    {:ok, hash} =
      DataPackages.store("meta.zip", "content", %{
        tool: "special",
        creator_uid: "user-123",
        keywords: ["tag1", "tag2"],
        mime_type: "application/zip"
      })

    {:ok, entry, _content} = DataPackages.get(hash)
    assert entry.tool == "special"
    assert entry.creator_uid == "user-123"
    assert entry.keywords == ["tag1", "tag2"]
    assert entry.mime_type == "application/zip"
  end
end
