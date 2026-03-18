defmodule ElixirTAK.COP.Identity do
  @moduledoc """
  Manages the dashboard's TAK identity: a persistent UID, callsign, and group.

  The UID is a UUID v4 generated on first use and persisted to `data/dashboard_uid`
  so it remains stable across server restarts. Callsign and group are read from
  application config with sensible defaults.

  TAK clients see dashboard-originated events as coming from this identity,
  enabling the COP to participate as a recognized entity in the TAK network.
  """

  use GenServer

  @uid_file "data/dashboard_uid"

  # -- Public API --------------------------------------------------------------

  @doc "Returns the persistent dashboard UID."
  @spec uid() :: String.t()
  def uid, do: GenServer.call(__MODULE__, :uid)

  @doc "Returns the configured dashboard callsign."
  @spec callsign() :: String.t()
  def callsign do
    Application.get_env(:elixir_tak, :dashboard_callsign, "ElixirTAK-COP")
  end

  @doc "Returns the configured dashboard group color."
  @spec group() :: String.t()
  def group do
    Application.get_env(:elixir_tak, :dashboard_group, "Cyan")
  end

  @doc "Returns the dashboard role (always HQ for command elements)."
  @spec role() :: String.t()
  def role, do: "HQ"

  # -- GenServer ---------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    uid = load_or_generate_uid()
    {:ok, %{uid: uid}}
  end

  @impl true
  def handle_call(:uid, _from, state) do
    {:reply, state.uid, state}
  end

  # -- Private -----------------------------------------------------------------

  defp load_or_generate_uid do
    case File.read(@uid_file) do
      {:ok, contents} ->
        uid = String.trim(contents)
        if uid != "", do: uid, else: generate_and_persist_uid()

      {:error, _} ->
        generate_and_persist_uid()
    end
  end

  defp generate_and_persist_uid do
    uid = uuid4()
    File.mkdir_p!(Path.dirname(@uid_file))
    File.write!(@uid_file, uid)
    uid
  end

  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<g1::binary-size(8), g2::binary-size(4), g3::binary-size(4), g4::binary-size(4),
        g5::binary-size(12)>> = hex

      "#{g1}-#{g2}-#{g3}-#{g4}-#{g5}"
    end)
  end
end
