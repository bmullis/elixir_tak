defmodule ElixirTAK.CertHelpers do
  @moduledoc """
  Shared utilities for certificate generation Mix tasks.

  Handles RSA key generation, X.509 certificate creation and signing,
  serial number tracking, PEM encoding, and PKCS12 bundle generation.
  """

  # -- Key Generation --------------------------------------------------------

  @doc "Generate an RSA private key with the given bit size (default 2048)."
  def generate_rsa_key(bits \\ 2048) do
    :public_key.generate_key({:rsa, bits, 65537})
  end

  @doc "Extract the public key from an RSA private key."
  def public_key(rsa_private_key) do
    # RSAPrivateKey record fields: modulus is elem 2, public_exponent is elem 3
    modulus = elem(rsa_private_key, 2)
    public_exponent = elem(rsa_private_key, 3)
    {:RSAPublicKey, modulus, public_exponent}
  end

  # -- Serial Number Tracking ------------------------------------------------

  @doc "Read the current serial number from serial.txt in the given directory."
  def read_serial(ca_dir) do
    path = Path.join(ca_dir, "serial.txt")

    case File.read(path) do
      {:ok, content} ->
        content |> String.trim() |> String.to_integer(16)

      {:error, :enoent} ->
        1
    end
  end

  @doc "Increment and write the next serial number."
  def next_serial!(ca_dir) do
    serial = read_serial(ca_dir)
    next = serial + 1

    File.write!(
      Path.join(ca_dir, "serial.txt"),
      Integer.to_string(next, 16) |> String.pad_leading(2, "0")
    )

    serial
  end

  # -- PEM Encoding/Decoding ------------------------------------------------

  @doc "Encode a DER-encoded certificate to PEM format."
  def encode_cert_pem(der_cert) do
    entry = {:Certificate, der_cert, :not_encrypted}
    :public_key.pem_encode([entry])
  end

  @doc "Encode an RSA private key to PEM format."
  def encode_key_pem(rsa_private_key) do
    der = :public_key.der_encode(:RSAPrivateKey, rsa_private_key)
    entry = {:RSAPrivateKey, der, :not_encrypted}
    :public_key.pem_encode([entry])
  end

  @doc "Decode a PEM file and return the first entry."
  def decode_pem_file!(path) do
    pem = File.read!(path)
    [entry | _] = :public_key.pem_decode(pem)
    :public_key.pem_entry_decode(entry)
  end

  @doc "Read a DER-encoded certificate from a PEM file."
  def read_cert_der!(path) do
    pem = File.read!(path)
    [{:Certificate, der, :not_encrypted} | _] = :public_key.pem_decode(pem)
    der
  end

  # -- X.509 Certificate Creation -------------------------------------------

  @doc "Create a self-signed CA certificate."
  def create_ca_cert(private_key, opts) do
    cn = Keyword.get(opts, :cn, "ElixirTAK CA")
    days = Keyword.get(opts, :days, 3650)
    serial = Keyword.get(opts, :serial, 1)

    subject = rdn_sequence(cn)
    validity = validity(days)
    pub_key = public_key(private_key)

    tbs =
      {:OTPTBSCertificate, :v3, serial, signature_algorithm(), subject, validity, subject,
       otp_subject_public_key_info(pub_key), :asn1_NOVALUE, :asn1_NOVALUE,
       [
         ca_extension(true),
         key_usage_extension([:keyCertSign, :cRLSign])
       ]}

    sign_certificate(tbs, private_key)
  end

  @doc "Create a server certificate signed by a CA."
  def create_server_cert(private_key, ca_key, ca_cert_der, opts) do
    cn = Keyword.get(opts, :cn, "localhost")
    days = Keyword.get(opts, :days, 365)
    serial = Keyword.get(opts, :serial, 2)
    san_entries = Keyword.get(opts, :san, [])

    ca_cert = :public_key.pkix_decode_cert(ca_cert_der, :otp)
    issuer = elem(elem(ca_cert, 1), 6)
    subject = rdn_sequence(cn)
    validity = validity(days)
    pub_key = public_key(private_key)

    extensions = [
      ca_extension(false),
      key_usage_extension([:digitalSignature, :keyEncipherment])
    ]

    extensions =
      if san_entries != [] do
        extensions ++ [san_extension(san_entries)]
      else
        extensions
      end

    tbs =
      {:OTPTBSCertificate, :v3, serial, signature_algorithm(), issuer, validity, subject,
       otp_subject_public_key_info(pub_key), :asn1_NOVALUE, :asn1_NOVALUE, extensions}

    sign_certificate(tbs, ca_key)
  end

  @doc "Create a client certificate signed by a CA."
  def create_client_cert(private_key, ca_key, ca_cert_der, opts) do
    cn = Keyword.fetch!(opts, :cn)
    days = Keyword.get(opts, :days, 365)
    serial = Keyword.get(opts, :serial, 3)

    ca_cert = :public_key.pkix_decode_cert(ca_cert_der, :otp)
    issuer = elem(elem(ca_cert, 1), 6)
    subject = rdn_sequence(cn)
    validity = validity(days)
    pub_key = public_key(private_key)

    tbs =
      {:OTPTBSCertificate, :v3, serial, signature_algorithm(), issuer, validity, subject,
       otp_subject_public_key_info(pub_key), :asn1_NOVALUE, :asn1_NOVALUE,
       [
         ca_extension(false),
         key_usage_extension([:digitalSignature])
       ]}

    sign_certificate(tbs, ca_key)
  end

  # -- PKCS12 Bundle Generation ---------------------------------------------

  @doc """
  Generate a PKCS12 (.p12) bundle using OpenSSL CLI.

  This is the most reliable way to create PKCS12 files compatible with
  Android/ATAK, since Erlang's :public_key doesn't have PKCS12 support.
  """
  def create_pkcs12!(cert_pem_path, key_pem_path, output_path, opts \\ []) do
    password = Keyword.get(opts, :password, "atakonline")
    ca_pem_path = Keyword.get(opts, :ca_cert)
    name = Keyword.get(opts, :name, "")

    args =
      [
        "pkcs12",
        "-export",
        "-in",
        cert_pem_path,
        "-inkey",
        key_pem_path,
        "-out",
        output_path,
        "-passout",
        "pass:#{password}",
        "-name",
        name
      ] ++
        if ca_pem_path, do: ["-certfile", ca_pem_path], else: []

    case System.cmd("openssl", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, "openssl pkcs12 failed (exit #{code}): #{output}"}
    end
  end

  @doc "Create a PKCS12 truststore containing only a CA certificate."
  def create_truststore_pkcs12!(ca_pem_path, output_path, opts \\ []) do
    password = Keyword.get(opts, :password, "atakonline")

    args = [
      "pkcs12",
      "-export",
      "-nokeys",
      "-in",
      ca_pem_path,
      "-out",
      output_path,
      "-passout",
      "pass:#{password}",
      "-name",
      "truststore"
    ]

    case System.cmd("openssl", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, "openssl pkcs12 failed (exit #{code}): #{output}"}
    end
  end

  # -- Certificate Fingerprint ----------------------------------------------

  @doc "Compute the SHA-256 fingerprint of a DER-encoded certificate."
  def fingerprint(der_cert) do
    :crypto.hash(:sha256, der_cert)
    |> Base.encode16(case: :upper)
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.join(":")
  end

  @doc "Get the expiry date from a DER-encoded certificate."
  def expiry(der_cert) do
    cert = :public_key.pkix_decode_cert(der_cert, :otp)
    {_not_before, not_after} = elem(elem(cert, 1), 5) |> elem(1)
    not_after
  end

  # -- SAN Parsing -----------------------------------------------------------

  @doc """
  Parse a SAN string like "DNS:localhost,IP:127.0.0.1" into OTP extension entries.
  """
  def parse_san(san_string) do
    san_string
    |> String.split(",", trim: true)
    |> Enum.map(fn entry ->
      case String.split(String.trim(entry), ":", parts: 2) do
        ["DNS", name] ->
          {:dNSName, to_charlist(name)}

        ["IP", ip_str] ->
          {:ok, ip} = :inet.parse_address(to_charlist(ip_str))
          {:iPAddress, :inet.ntoa(ip)}

        _ ->
          {:dNSName, to_charlist(String.trim(entry))}
      end
    end)
  end

  # -- Private helpers -------------------------------------------------------

  defp sign_certificate(tbs, private_key) do
    tbs_der = :public_key.pkix_encode(:OTPTBSCertificate, tbs, :otp)
    signature = :public_key.sign(tbs_der, :sha256, private_key)

    cert =
      {:OTPCertificate, tbs, signature_algorithm(), signature}

    :public_key.pkix_encode(:OTPCertificate, cert, :otp)
  end

  defp signature_algorithm do
    {:SignatureAlgorithm, {1, 2, 840, 113_549, 1, 1, 11}, :asn1_NOVALUE}
  end

  defp rdn_sequence(cn) do
    {:rdnSequence, [[{:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, cn}}]]}
  end

  defp validity(days) do
    now = DateTime.utc_now()
    not_before = format_generalized_time(now)
    not_after = format_generalized_time(DateTime.add(now, days * 86400))
    {:Validity, {:generalTime, not_before}, {:generalTime, not_after}}
  end

  defp format_generalized_time(dt) do
    Calendar.strftime(dt, "%Y%m%d%H%M%SZ") |> to_charlist()
  end

  defp otp_subject_public_key_info(pub_key) do
    algo = {:PublicKeyAlgorithm, {1, 2, 840, 113_549, 1, 1, 1}, :asn1_NOVALUE}
    {:OTPSubjectPublicKeyInfo, algo, pub_key}
  end

  defp ca_extension(is_ca) do
    {:Extension, {2, 5, 29, 19}, true, {:BasicConstraints, is_ca, :asn1_NOVALUE}}
  end

  defp key_usage_extension(usages) do
    {:Extension, {2, 5, 29, 15}, true, usages}
  end

  defp san_extension(entries) do
    {:Extension, {2, 5, 29, 17}, false, entries}
  end
end
