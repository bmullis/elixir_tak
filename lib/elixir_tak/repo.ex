defmodule ElixirTAK.Repo do
  @moduledoc "Ecto repo backed by SQLite3 for event history persistence."

  use Ecto.Repo,
    otp_app: :elixir_tak,
    adapter: Ecto.Adapters.SQLite3
end
