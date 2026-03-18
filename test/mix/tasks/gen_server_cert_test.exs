defmodule Mix.Tasks.ElixirTak.GenServerCertTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    ca_dir = Path.join(tmp_dir, "ca")
    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir, "--cn", "Test CA"])
    %{ca_dir: ca_dir}
  end

  @tag :tmp_dir
  test "generates server cert signed by CA", %{tmp_dir: tmp_dir, ca_dir: ca_dir} do
    out_dir = Path.join(tmp_dir, "server")

    Mix.Tasks.ElixirTak.GenServerCert.run([
      "--ca-dir",
      ca_dir,
      "--out-dir",
      out_dir,
      "--cn",
      "myserver",
      "--san",
      "DNS:myserver,IP:10.0.0.1"
    ])

    assert File.exists?(Path.join(out_dir, "server.pem"))
    assert File.exists?(Path.join(out_dir, "server-key.pem"))

    # Cert is parseable
    cert_der = ElixirTAK.CertHelpers.read_cert_der!(Path.join(out_dir, "server.pem"))
    cert = :public_key.pkix_decode_cert(cert_der, :otp)
    assert elem(cert, 0) == :OTPCertificate

    # Verify cert is signed by CA
    assert :public_key.pkix_verify(
             cert_der,
             ElixirTAK.CertHelpers.public_key(
               ElixirTAK.CertHelpers.decode_pem_file!(Path.join(ca_dir, "ca-key.pem"))
             )
           )
  end

  @tag :tmp_dir
  test "increments serial number", %{tmp_dir: tmp_dir, ca_dir: ca_dir} do
    out1 = Path.join(tmp_dir, "server1")
    out2 = Path.join(tmp_dir, "server2")

    Mix.Tasks.ElixirTak.GenServerCert.run(["--ca-dir", ca_dir, "--out-dir", out1])
    Mix.Tasks.ElixirTak.GenServerCert.run(["--ca-dir", ca_dir, "--out-dir", out2])

    # Serial should have been incremented twice from 02
    serial = ElixirTAK.CertHelpers.read_serial(ca_dir)
    assert serial == 4
  end
end
