defmodule ElixirTAK.CertStore do
  @moduledoc """
  Simple certificate approval/revocation store backed by ETS.

  Tracks certificate serial numbers as :approved or :revoked.
  Used by CotHandler to reject connections from revoked certs.
  """

  use GenServer

  require Logger

  @table :cert_store

  # -- Public API ------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Check if a certificate serial is revoked. Returns true if revoked."
  def revoked?(serial) when is_integer(serial) do
    case :ets.lookup(@table, serial) do
      [{^serial, :revoked}] -> true
      _ -> false
    end
  end

  def revoked?(_), do: false

  @doc "Mark a certificate serial as revoked."
  def revoke(serial) when is_integer(serial) do
    :ets.insert(@table, {serial, :revoked})
    Logger.info("Certificate serial #{Integer.to_string(serial, 16)} revoked")
    :ok
  end

  @doc "Mark a certificate serial as approved."
  def approve(serial) when is_integer(serial) do
    :ets.insert(@table, {serial, :approved})
    :ok
  end

  @doc "List all entries. Returns list of {serial, status} tuples."
  def list do
    :ets.tab2list(@table)
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, []}
  end
end
