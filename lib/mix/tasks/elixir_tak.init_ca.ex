defmodule Mix.Tasks.ElixirTak.InitCa do
  @moduledoc """
  Initialize a Certificate Authority for ElixirTAK.

  Creates a self-signed CA certificate and private key.

  ## Usage

      mix elixir_tak.init_ca [--dir certs/ca] [--cn "My TAK CA"] [--days 3650] [--force]
  """

  use Mix.Task

  alias ElixirTAK.CertHelpers

  @shortdoc "Create a new Certificate Authority"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [dir: :string, cn: :string, days: :integer, force: :boolean]
      )

    dir = Keyword.get(opts, :dir, "certs/ca")
    cn = Keyword.get(opts, :cn, "ElixirTAK CA")
    days = Keyword.get(opts, :days, 3650)
    force = Keyword.get(opts, :force, false)

    cert_path = Path.join(dir, "ca.pem")
    key_path = Path.join(dir, "ca-key.pem")

    if File.exists?(cert_path) and not force do
      Mix.shell().error("CA already exists at #{dir}. Use --force to overwrite.")
      exit({:shutdown, 1})
    end

    File.mkdir_p!(dir)

    Mix.shell().info("Generating CA key pair...")
    private_key = CertHelpers.generate_rsa_key(4096)

    Mix.shell().info("Creating self-signed CA certificate (CN=#{cn}, valid #{days} days)...")
    cert_der = CertHelpers.create_ca_cert(private_key, cn: cn, days: days, serial: 1)

    File.write!(cert_path, CertHelpers.encode_cert_pem(cert_der))
    File.write!(key_path, CertHelpers.encode_key_pem(private_key))
    File.write!(Path.join(dir, "serial.txt"), "02")

    fingerprint = CertHelpers.fingerprint(cert_der)

    Mix.shell().info("""

    CA created successfully!
      Directory:   #{dir}
      Certificate: #{cert_path}
      Key:         #{key_path}
      CN:          #{cn}
      Valid:       #{days} days
      Fingerprint: #{fingerprint}
    """)
  end
end
