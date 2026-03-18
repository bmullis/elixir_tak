defmodule Mix.Tasks.ElixirTak.GenClientCertTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    ca_dir = Path.join(tmp_dir, "ca")
    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir, "--cn", "Test CA"])
    %{ca_dir: ca_dir}
  end

  @tag :tmp_dir
  test "generates client cert, key, and p12", %{tmp_dir: tmp_dir, ca_dir: ca_dir} do
    out_dir = Path.join(tmp_dir, "client")

    Mix.Tasks.ElixirTak.GenClientCert.run([
      "--cn",
      "SGT.Test",
      "--ca-dir",
      ca_dir,
      "--out-dir",
      out_dir
    ])

    assert File.exists?(Path.join(out_dir, "client.pem"))
    assert File.exists?(Path.join(out_dir, "client-key.pem"))
    assert File.exists?(Path.join(out_dir, "client.p12"))

    # Cert is signed by CA
    cert_der = ElixirTAK.CertHelpers.read_cert_der!(Path.join(out_dir, "client.pem"))
    ca_key = ElixirTAK.CertHelpers.decode_pem_file!(Path.join(ca_dir, "ca-key.pem"))
    assert :public_key.pkix_verify(cert_der, ElixirTAK.CertHelpers.public_key(ca_key))
  end

  @tag :tmp_dir
  test "raises without --cn", %{tmp_dir: tmp_dir, ca_dir: ca_dir} do
    assert_raise Mix.Error, ~r/--cn is required/, fn ->
      Mix.Tasks.ElixirTak.GenClientCert.run([
        "--ca-dir",
        ca_dir,
        "--out-dir",
        Path.join(tmp_dir, "client")
      ])
    end
  end
end
