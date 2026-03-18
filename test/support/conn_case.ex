defmodule ElixirTAKWeb.ConnCase do
  @moduledoc """
  Test case for Phoenix controller tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      @endpoint ElixirTAKWeb.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
