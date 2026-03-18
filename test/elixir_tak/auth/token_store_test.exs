defmodule ElixirTAK.Auth.TokenStoreTest do
  use ElixirTAK.DataCase, async: false

  alias ElixirTAK.Auth.{TokenStore, ApiToken}

  setup do
    # Allow persistent GenServers to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), TokenStore)
    Ecto.Adapters.SQL.Sandbox.allow(ElixirTAK.Repo, self(), ElixirTAK.Auth.AuditLog)

    # Clear ETS between tests
    :ets.delete_all_objects(:api_tokens)
    :ok
  end

  describe "create/3" do
    test "creates a token and returns the raw value" do
      assert {:ok, raw_token, record} = TokenStore.create("test-token", "admin")
      assert is_binary(raw_token)
      assert record.name == "test-token"
      assert record.role == "admin"
      assert record.active == true
    end

    test "token is findable via lookup" do
      {:ok, raw_token, _record} = TokenStore.create("lookup-test", "viewer")
      assert {:ok, found} = TokenStore.lookup(raw_token)
      assert found.name == "lookup-test"
      assert found.role == "viewer"
    end

    test "rejects invalid roles" do
      assert {:error, _changeset} = TokenStore.create("bad-role", "superuser")
    end
  end

  describe "lookup/1" do
    test "returns :not_found for unknown tokens" do
      assert :not_found = TokenStore.lookup("nonexistent-token")
    end

    test "returns :not_found for revoked tokens" do
      {:ok, raw_token, record} = TokenStore.create("revoke-test", "viewer")
      TokenStore.revoke(record.id)
      assert :not_found = TokenStore.lookup(raw_token)
    end

    test "returns :not_found for expired tokens" do
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:microsecond)

      {:ok, raw_token, _record} =
        TokenStore.create("expired-test", "viewer", expires_at: expired_at)

      assert :not_found = TokenStore.lookup(raw_token)
    end
  end

  describe "revoke/1" do
    test "deactivates a token" do
      {:ok, _raw, record} = TokenStore.create("to-revoke", "operator")
      assert :ok = TokenStore.revoke(record.id)
    end

    test "returns :not_found for unknown ID" do
      assert :not_found = TokenStore.revoke(Ecto.UUID.generate())
    end
  end

  describe "delete/1" do
    test "permanently removes a token" do
      {:ok, raw_token, record} = TokenStore.create("to-delete", "viewer")
      assert :ok = TokenStore.delete(record.id)
      assert :not_found = TokenStore.lookup(raw_token)
    end
  end

  describe "list/0" do
    test "returns all tokens" do
      TokenStore.create("token-a", "admin")
      TokenStore.create("token-b", "viewer")
      tokens = TokenStore.list()
      names = Enum.map(tokens, & &1.name)
      assert "token-a" in names
      assert "token-b" in names
    end
  end

  describe "ApiToken" do
    test "hash_token is deterministic" do
      assert ApiToken.hash_token("abc") == ApiToken.hash_token("abc")
    end

    test "generate_raw_token produces unique values" do
      a = ApiToken.generate_raw_token()
      b = ApiToken.generate_raw_token()
      assert a != b
    end
  end
end
