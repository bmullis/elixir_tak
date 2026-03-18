defmodule ElixirTAKWeb do
  @moduledoc """
  The entrypoint for defining web interface components.

  Provides macros for router and component definitions.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false
    end
  end

  def component do
    quote do
      use Phoenix.Component
      import Phoenix.HTML

      unquote(verified_routes())
    end
  end

  defp verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: ElixirTAKWeb.Endpoint,
        router: ElixirTAKWeb.Router
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
