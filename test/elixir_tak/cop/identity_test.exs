defmodule ElixirTAK.COP.IdentityTest do
  use ExUnit.Case, async: false

  alias ElixirTAK.COP.Identity

  describe "uid/0" do
    test "returns a UUID v4 string" do
      uid = Identity.uid()
      assert is_binary(uid)
      assert String.length(uid) == 36

      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               uid
             )
    end

    test "returns the same UID on repeated calls" do
      uid1 = Identity.uid()
      uid2 = Identity.uid()
      assert uid1 == uid2
    end
  end

  describe "callsign/0" do
    test "returns the configured callsign" do
      assert is_binary(Identity.callsign())
    end

    test "defaults to ElixirTAK-COP" do
      assert Identity.callsign() == "ElixirTAK-COP"
    end
  end

  describe "group/0" do
    test "returns the configured group" do
      assert is_binary(Identity.group())
    end

    test "defaults to Cyan" do
      assert Identity.group() == "Cyan"
    end
  end

  describe "role/0" do
    test "returns HQ" do
      assert Identity.role() == "HQ"
    end
  end
end
