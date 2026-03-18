defmodule ElixirTAK.CertManager do
  @moduledoc """
  High-level certificate management operations.

  Extracts the shared logic from Mix tasks so both CLI and API can
  generate client certificates and connection profiles.
  """

  alias ElixirTAK.CertHelpers
  alias ElixirTAK.CertStore

  @default_password "atakonline"

  @doc """
  Generate a client certificate signed by the CA.

  Options:
    - `:cn` (required) - Common Name for the certificate
    - `:ca_dir` - CA directory (default: configured or "certs/ca")
    - `:days` - validity period in days (default: 365)
    - `:p12_pass` - PKCS12 password (default: from env or "atakonline")

  Returns `{:ok, info_map}` or `{:error, reason}`.
  """
  def generate_client_cert(opts) do
    cn = Keyword.fetch!(opts, :cn)
    ca_dir = Keyword.get(opts, :ca_dir, ca_dir())
    days = Keyword.get(opts, :days, 365)
    p12_pass = Keyword.get(opts, :p12_pass, p12_password())
    out_dir = Keyword.get(opts, :out_dir, client_dir(cn))

    with {:ok, ca_cert_der} <-
           read_file(Path.join(ca_dir, "ca.pem"), &CertHelpers.read_cert_der!/1),
         {:ok, ca_key} <-
           read_file(Path.join(ca_dir, "ca-key.pem"), &CertHelpers.decode_pem_file!/1) do
      serial = CertHelpers.next_serial!(ca_dir)
      File.mkdir_p!(out_dir)

      client_key = CertHelpers.generate_rsa_key(2048)

      cert_der =
        CertHelpers.create_client_cert(client_key, ca_key, ca_cert_der,
          cn: cn,
          days: days,
          serial: serial
        )

      cert_path = Path.join(out_dir, "client.pem")
      key_path = Path.join(out_dir, "client-key.pem")
      p12_path = Path.join(out_dir, "client.p12")

      File.write!(cert_path, CertHelpers.encode_cert_pem(cert_der))
      File.write!(key_path, CertHelpers.encode_key_pem(client_key))

      case CertHelpers.create_pkcs12!(cert_path, key_path, p12_path,
             password: p12_pass,
             ca_cert: Path.join(ca_dir, "ca.pem"),
             name: cn
           ) do
        :ok -> :ok
        {:error, msg} -> {:error, "PKCS12 generation failed: #{msg}"}
      end
      |> case do
        :ok ->
          CertStore.approve(serial)
          fingerprint = CertHelpers.fingerprint(cert_der)

          {:ok,
           %{
             cn: cn,
             serial: serial,
             fingerprint: fingerprint,
             created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
             out_dir: out_dir
           }}

        error ->
          error
      end
    end
  end

  @doc """
  Generate an ATAK-importable connection profile zip.

  Options:
    - `:cn` (required) - Common Name (must have existing client cert)
    - `:host` (required) - server hostname or IP
    - `:port` - TLS port (default: 8089)
    - `:ca_dir` - CA directory
    - `:client_dir` - client cert directory
    - `:p12_pass` - PKCS12 password

  Returns `{:ok, zip_binary}` or `{:error, reason}`.
  """
  def generate_profile(opts) do
    cn = Keyword.fetch!(opts, :cn)
    host = Keyword.fetch!(opts, :host)
    tls_port = Keyword.get(opts, :port, 8089)
    ca_dir = Keyword.get(opts, :ca_dir, ca_dir())
    client_dir_path = Keyword.get(opts, :client_dir, client_dir(cn))
    p12_pass = Keyword.get(opts, :p12_pass, p12_password())

    ca_pem_path = Path.join(ca_dir, "ca.pem")
    client_cert_path = Path.join(client_dir_path, "client.pem")
    client_key_path = Path.join(client_dir_path, "client-key.pem")

    missing =
      [ca_pem_path, client_cert_path, client_key_path]
      |> Enum.reject(&File.exists?/1)

    if missing != [] do
      {:error, "Required files not found: #{Enum.join(missing, ", ")}"}
    else
      build_profile_zip(
        cn,
        host,
        tls_port,
        ca_pem_path,
        client_cert_path,
        client_key_path,
        p12_pass
      )
    end
  end

  @doc """
  List all client certificates by scanning the client cert directories
  and cross-referencing with CertStore.
  """
  def list_certs do
    base = clients_base_dir()
    store_entries = CertStore.list() |> Map.new()

    case File.ls(base) do
      {:ok, dirs} ->
        certs =
          dirs
          |> Enum.map(fn dir ->
            cert_path = Path.join([base, dir, "client.pem"])

            if File.exists?(cert_path) do
              try do
                der = CertHelpers.read_cert_der!(cert_path)
                cert = :public_key.pkix_decode_cert(der, :otp)
                tbs = elem(cert, 1)
                serial = elem(tbs, 2)

                cn = extract_cn(tbs)
                fingerprint = CertHelpers.fingerprint(der)
                status = Map.get(store_entries, serial, :unknown)

                %{
                  cn: cn,
                  serial: serial,
                  fingerprint: fingerprint,
                  status: to_string(status),
                  directory: dir
                }
              rescue
                _ -> nil
              end
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, certs}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  @doc """
  Revoke a certificate by serial number.
  """
  def revoke_cert(serial) when is_integer(serial) do
    CertStore.revoke(serial)
    :ok
  end

  # -- Private ---------------------------------------------------------------

  defp build_profile_zip(
         cn,
         host,
         tls_port,
         ca_pem_path,
         client_cert_path,
         client_key_path,
         p12_pass
       ) do
    tmp_dir = Path.join(System.tmp_dir!(), "elixir_tak_profile_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    try do
      truststore_path = Path.join(tmp_dir, "truststore-root.p12")

      with :ok <-
             CertHelpers.create_truststore_pkcs12!(ca_pem_path, truststore_path,
               password: p12_pass
             ) do
        client_p12_path = Path.join(tmp_dir, "#{cn}.p12")

        with :ok <-
               CertHelpers.create_pkcs12!(client_cert_path, client_key_path, client_p12_path,
                 password: p12_pass,
                 ca_cert: ca_pem_path,
                 name: cn
               ) do
          uid = uuid4()
          manifest = manifest_xml(uid, cn)
          pref = pref_xml(cn, host, tls_port, p12_pass)

          files = [
            {~c"truststore-root.p12", File.read!(truststore_path)},
            {~c"#{cn}.p12", File.read!(client_p12_path)},
            {~c"manifest.xml", manifest},
            {~c"#{cn}.pref", pref}
          ]

          case :zip.create(~c"profile.zip", files, [:memory]) do
            {:ok, {_, zip_binary}} -> {:ok, zip_binary}
            {:error, reason} -> {:error, "Failed to create zip: #{inspect(reason)}"}
          end
        end
      end
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp extract_cn(tbs) do
    {:rdnSequence, rdn_list} = elem(tbs, 6)

    Enum.find_value(rdn_list, "unknown", fn attrs ->
      Enum.find_value(attrs, nil, fn
        {:AttributeTypeAndValue, {2, 5, 4, 3}, value} ->
          extract_string_value(value)

        _ ->
          nil
      end)
    end)
  end

  defp extract_string_value({:utf8String, s}) when is_binary(s), do: s
  defp extract_string_value({:utf8String, s}) when is_list(s), do: to_string(s)
  defp extract_string_value({:printableString, s}) when is_list(s), do: to_string(s)
  defp extract_string_value({:printableString, s}) when is_binary(s), do: s
  defp extract_string_value(s) when is_binary(s), do: s
  defp extract_string_value(s) when is_list(s), do: to_string(s)
  defp extract_string_value(_), do: "unknown"

  defp manifest_xml(uid, cn) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <MissionPackageManifest version="2">
      <Configuration>
        <Parameter name="uid" value="#{uid}"/>
        <Parameter name="name" value="ElixirTAK Connection Profile"/>
      </Configuration>
      <Contents>
        <Content zipEntry="truststore-root.p12">
          <Parameter name="type" value="com.atakmap.app_preferences.sslTrustCert"/>
        </Content>
        <Content zipEntry="#{cn}.p12">
          <Parameter name="type" value="com.atakmap.app_preferences.sslClientCert"/>
        </Content>
        <Content zipEntry="#{cn}.pref">
          <Parameter name="type" value="com.atakmap.app_preferences"/>
        </Content>
      </Contents>
    </MissionPackageManifest>
    """
  end

  defp pref_xml(cn, host, tls_port, p12_pass) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <preferences>
      <preference version="1" name="cot_streams">
        <entry key="count" class="class java.lang.Integer">1</entry>
        <entry key="description0" class="class java.lang.String">ElixirTAK</entry>
        <entry key="enabled0" class="class java.lang.Boolean">true</entry>
        <entry key="connectString0" class="class java.lang.String">#{host}:#{tls_port}:ssl</entry>
      </preference>
      <preference version="1" name="com.atakmap.app_preferences">
        <entry key="clientPassword" class="class java.lang.String">#{p12_pass}</entry>
        <entry key="caPassword" class="class java.lang.String">#{p12_pass}</entry>
        <entry key="certificateLocation" class="class java.lang.String">/cert/#{cn}.p12</entry>
        <entry key="caLocation" class="class java.lang.String">/cert/truststore-root.p12</entry>
      </preference>
    </preferences>
    """
  end

  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    [a, b, c]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> then(fn [a, b, c] ->
      a = String.pad_leading(a, 12, "0")
      b = String.pad_leading(b, 4, "0")
      c = String.pad_leading(c, 16, "0")

      "#{String.slice(a, 0, 8)}-#{String.slice(a, 8, 4)}-4#{String.slice(b, 1, 3)}-#{String.slice(c, 0, 4)}-#{String.slice(c, 4, 12)}"
    end)
    |> String.downcase()
  end

  defp read_file(path, decoder) do
    if File.exists?(path) do
      {:ok, decoder.(path)}
    else
      {:error, "File not found: #{path}"}
    end
  rescue
    e -> {:error, "Failed to read #{path}: #{Exception.message(e)}"}
  end

  defp ca_dir do
    Application.get_env(:elixir_tak, :ca_dir, "certs")
  end

  defp client_dir(cn) do
    Path.join(clients_base_dir(), slugify(cn))
  end

  defp clients_base_dir do
    Application.get_env(:elixir_tak, :clients_dir, "certs/clients")
  end

  defp p12_password do
    System.get_env("TAK_CERT_PASSWORD", @default_password)
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
