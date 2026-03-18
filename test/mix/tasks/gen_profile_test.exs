defmodule Mix.Tasks.ElixirTak.GenProfileTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    ca_dir = Path.join(tmp_dir, "ca")
    client_dir = Path.join(tmp_dir, "client")

    Mix.Tasks.ElixirTak.InitCa.run(["--dir", ca_dir, "--cn", "Test CA"])

    Mix.Tasks.ElixirTak.GenClientCert.run([
      "--cn",
      "TestUser",
      "--ca-dir",
      ca_dir,
      "--out-dir",
      client_dir
    ])

    %{ca_dir: ca_dir, client_dir: client_dir}
  end

  @tag :tmp_dir
  test "generates profile zip with expected files", %{
    tmp_dir: tmp_dir,
    ca_dir: ca_dir,
    client_dir: client_dir
  } do
    out_path = Path.join(tmp_dir, "profile.zip")

    Mix.Tasks.ElixirTak.GenProfile.run([
      "--cn",
      "TestUser",
      "--host",
      "10.0.0.1",
      "--tls-port",
      "8089",
      "--ca-dir",
      ca_dir,
      "--client-dir",
      client_dir,
      "--out",
      out_path
    ])

    assert File.exists?(out_path)

    {:ok, files} = :zip.list_dir(to_charlist(out_path))

    filenames =
      files
      |> Enum.filter(fn
        {:zip_file, _, _, _, _, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

    assert "truststore-root.p12" in filenames
    assert "TestUser.p12" in filenames
    assert "manifest.xml" in filenames
    assert "TestUser.pref" in filenames
  end

  @tag :tmp_dir
  test "manifest.xml contains correct structure", %{
    tmp_dir: tmp_dir,
    ca_dir: ca_dir,
    client_dir: client_dir
  } do
    out_path = Path.join(tmp_dir, "profile.zip")

    Mix.Tasks.ElixirTak.GenProfile.run([
      "--cn",
      "TestUser",
      "--host",
      "10.0.0.1",
      "--ca-dir",
      ca_dir,
      "--client-dir",
      client_dir,
      "--out",
      out_path
    ])

    {:ok, zip_files} = :zip.extract(to_charlist(out_path), [:memory])

    {_, manifest} =
      Enum.find(zip_files, fn {name, _} -> to_string(name) == "manifest.xml" end)

    manifest_str = to_string(manifest)
    assert manifest_str =~ "MissionPackageManifest"
    assert manifest_str =~ "truststore-root.p12"
    assert manifest_str =~ "TestUser.p12"
    assert manifest_str =~ "TestUser.pref"
  end

  @tag :tmp_dir
  test "pref file contains connection string", %{
    tmp_dir: tmp_dir,
    ca_dir: ca_dir,
    client_dir: client_dir
  } do
    out_path = Path.join(tmp_dir, "profile.zip")

    Mix.Tasks.ElixirTak.GenProfile.run([
      "--cn",
      "TestUser",
      "--host",
      "192.168.1.50",
      "--tls-port",
      "9999",
      "--ca-dir",
      ca_dir,
      "--client-dir",
      client_dir,
      "--out",
      out_path
    ])

    {:ok, zip_files} = :zip.extract(to_charlist(out_path), [:memory])

    {_, pref} =
      Enum.find(zip_files, fn {name, _} -> to_string(name) == "TestUser.pref" end)

    pref_str = to_string(pref)
    assert pref_str =~ "192.168.1.50:9999:ssl"
  end
end
