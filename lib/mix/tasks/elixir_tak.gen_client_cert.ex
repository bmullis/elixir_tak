defmodule Mix.Tasks.ElixirTak.GenClientCert do
  @moduledoc """
  Generate a client certificate signed by the CA.

  ## Usage

      mix elixir_tak.gen_client_cert --cn "SGT.Smith" [--ca-dir certs/ca]
          [--out-dir certs/clients/sgt-smith] [--days 365] [--p12-pass atakonline]
  """

  use Mix.Task

  alias ElixirTAK.CertManager

  @shortdoc "Generate a client certificate"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          cn: :string,
          ca_dir: :string,
          out_dir: :string,
          days: :integer,
          p12_pass: :string
        ]
      )

    cn = Keyword.get(opts, :cn) || Mix.raise("--cn is required")

    # Ensure CertStore is started for approve/revoke tracking
    {:ok, _} = Application.ensure_all_started(:elixir_tak)

    manager_opts =
      [cn: cn]
      |> maybe_put(opts, :ca_dir)
      |> maybe_put(opts, :out_dir)
      |> maybe_put(opts, :days)
      |> maybe_put(opts, :p12_pass)

    Mix.shell().info("Generating client certificate (CN=#{cn})...")

    case CertManager.generate_client_cert(manager_opts) do
      {:ok, info} ->
        Mix.shell().info("""

        Client certificate created!
          Directory:   #{info.out_dir}
          CN:          #{info.cn}
          Serial:      #{info.serial}
          Fingerprint: #{info.fingerprint}
        """)

      {:error, reason} ->
        Mix.raise("Failed to generate client cert: #{reason}")
    end
  end

  defp maybe_put(acc, opts, key) do
    case Keyword.get(opts, key) do
      nil -> acc
      val -> Keyword.put(acc, key, val)
    end
  end
end
