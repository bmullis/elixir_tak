defmodule Mix.Tasks.ElixirTak.GenProfile do
  @moduledoc """
  Generate an ATAK-importable connection profile zip.

  ## Usage

      mix elixir_tak.gen_profile --cn "SGT.Smith" --host 192.168.1.100
          [--tls-port 8089] [--ca-dir certs/ca]
          [--client-dir certs/clients/sgt-smith] [--out profile.zip]
          [--p12-pass atakonline]
  """

  use Mix.Task

  alias ElixirTAK.CertManager

  @shortdoc "Generate an ATAK connection profile"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          cn: :string,
          host: :string,
          tls_port: :integer,
          ca_dir: :string,
          client_dir: :string,
          out: :string,
          p12_pass: :string
        ]
      )

    cn = Keyword.get(opts, :cn) || Mix.raise("--cn is required")
    host = Keyword.get(opts, :host) || Mix.raise("--host is required")
    tls_port = Keyword.get(opts, :tls_port, 8089)
    out_path = Keyword.get(opts, :out, "profile-#{slugify(cn)}.zip")

    manager_opts =
      [cn: cn, host: host, port: tls_port]
      |> maybe_put(opts, :ca_dir)
      |> maybe_put(opts, :client_dir)
      |> maybe_put(opts, :p12_pass)

    Mix.shell().info("Generating connection profile for #{cn}...")

    case CertManager.generate_profile(manager_opts) do
      {:ok, zip_binary} ->
        File.write!(out_path, zip_binary)

        Mix.shell().info("""

        Connection profile created!
          Output:    #{out_path}
          CN:        #{cn}
          Server:    #{host}:#{tls_port} (SSL)

        Import this zip file into ATAK via Settings > Import.
        """)

      {:error, reason} ->
        Mix.raise("Failed to generate profile: #{reason}")
    end
  end

  defp maybe_put(acc, opts, key) do
    case Keyword.get(opts, key) do
      nil -> acc
      val -> Keyword.put(acc, key, val)
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
