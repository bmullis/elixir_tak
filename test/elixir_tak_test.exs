defmodule ElixirTAKTest do
  use ExUnit.Case
  doctest ElixirTAK

  test "greets the world" do
    assert ElixirTAK.hello() == :world
  end
end
