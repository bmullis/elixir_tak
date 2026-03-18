defmodule ElixirTAK.DataCase do
  @moduledoc """
  Test case for tests that require database access.

  Sets up the Ecto SQL Sandbox for test isolation.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ElixirTAK.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ElixirTAK.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ElixirTAK.Repo, shared: !tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
