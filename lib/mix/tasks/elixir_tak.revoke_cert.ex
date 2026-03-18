defmodule Mix.Tasks.ElixirTak.RevokeCert do
  @moduledoc """
  Revoke a client certificate by serial number.

  ## Usage

      mix elixir_tak.revoke_cert --serial 03

  The serial number is in hex format (as shown in serial.txt).
  The server must be running for this to take effect immediately.
  """

  use Mix.Task

  @shortdoc "Revoke a client certificate"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [serial: :string])

    serial_hex = Keyword.get(opts, :serial) || Mix.raise("--serial is required")
    serial = String.to_integer(serial_hex, 16)

    # Ensure the app is started so CertStore ETS table exists
    Mix.Task.run("app.start")

    ElixirTAK.CertStore.revoke(serial)
    Mix.shell().info("Certificate serial #{serial_hex} (#{serial}) has been revoked.")
  end
end
