defmodule ElixirTAKWeb.DashboardSocket do
  @moduledoc "Phoenix socket for the React dashboard channel."

  use Phoenix.Socket

  channel("dashboard:cop", ElixirTAKWeb.DashboardChannel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
