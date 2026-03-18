defmodule Mix.Tasks.ElixirTak.GenServerCert do
  @moduledoc """
  Generate a server certificate signed by the CA.

  ## Usage

      mix elixir_tak.gen_server_cert [--ca-dir certs/ca] [--out-dir certs/server]
          [--cn localhost] [--san "DNS:localhost,IP:127.0.0.1"] [--days 365]
  """

  use Mix.Task

  alias ElixirTAK.CertHelpers

  @shortdoc "Generate a server certificate"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [ca_dir: :string, out_dir: :string, cn: :string, san: :string, days: :integer]
      )

    ca_dir = Keyword.get(opts, :ca_dir, "certs/ca")
    out_dir = Keyword.get(opts, :out_dir, "certs/server")
    cn = Keyword.get(opts, :cn, "localhost")
    san_str = Keyword.get(opts, :san, "DNS:localhost,IP:127.0.0.1")
    days = Keyword.get(opts, :days, 365)

    ca_cert_der = CertHelpers.read_cert_der!(Path.join(ca_dir, "ca.pem"))
    ca_key = CertHelpers.decode_pem_file!(Path.join(ca_dir, "ca-key.pem"))
    serial = CertHelpers.next_serial!(ca_dir)
    san_entries = CertHelpers.parse_san(san_str)

    File.mkdir_p!(out_dir)

    Mix.shell().info("Generating server key pair...")
    server_key = CertHelpers.generate_rsa_key(2048)

    Mix.shell().info("Creating server certificate (CN=#{cn}, serial=#{serial})...")

    cert_der =
      CertHelpers.create_server_cert(server_key, ca_key, ca_cert_der,
        cn: cn,
        days: days,
        serial: serial,
        san: san_entries
      )

    cert_path = Path.join(out_dir, "server.pem")
    key_path = Path.join(out_dir, "server-key.pem")

    File.write!(cert_path, CertHelpers.encode_cert_pem(cert_der))
    File.write!(key_path, CertHelpers.encode_key_pem(server_key))

    fingerprint = CertHelpers.fingerprint(cert_der)

    Mix.shell().info("""

    Server certificate created!
      Certificate: #{cert_path}
      Key:         #{key_path}
      CN:          #{cn}
      Serial:      #{serial}
      SAN:         #{san_str}
      Valid:       #{days} days
      Fingerprint: #{fingerprint}

    Add to config/dev.exs:

      config :elixir_tak,
        certfile: "#{cert_path}",
        keyfile: "#{key_path}",
        cacertfile: "#{Path.join(ca_dir, "ca.pem")}"
    """)
  end
end
