defmodule Mix.Tasks.ElixirTak.InitCaTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "creates CA cert, key, and serial file", %{tmp_dir: tmp_dir} do
    ca_dir = Path.join(tmp_dir, "ca")

    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir, "--cn", "Test CA", "--days", "365"])

    assert File.exists?(Path.join(ca_dir, "ca.pem"))
    assert File.exists?(Path.join(ca_dir, "ca-key.pem"))
    assert File.exists?(Path.join(ca_dir, "serial.txt"))

    # Serial starts at 02 (01 used by the CA itself)
    assert File.read!(Path.join(ca_dir, "serial.txt")) |> String.trim() == "02"

    # CA cert is valid and parseable
    cert_der = ElixirTAK.CertHelpers.read_cert_der!(Path.join(ca_dir, "ca.pem"))
    cert = :public_key.pkix_decode_cert(cert_der, :otp)
    assert elem(cert, 0) == :OTPCertificate

    # Key is parseable
    key = ElixirTAK.CertHelpers.decode_pem_file!(Path.join(ca_dir, "ca-key.pem"))
    assert elem(key, 0) == :RSAPrivateKey
  end

  @tag :tmp_dir
  test "refuses to overwrite without --force", %{tmp_dir: tmp_dir} do
    ca_dir = Path.join(tmp_dir, "ca")
    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir])

    assert catch_exit(Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir])) == {:shutdown, 1}
  end

  @tag :tmp_dir
  test "--force overwrites existing CA", %{tmp_dir: tmp_dir} do
    ca_dir = Path.join(tmp_dir, "ca")
    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir])
    original = File.read!(Path.join(ca_dir, "ca.pem"))

    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir, "--force"])
    new = File.read!(Path.join(ca_dir, "ca.pem"))

    assert original != new
  end
end
