#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/certs"
DAYS=3650

echo "Generating dev certificates in $CERT_DIR"
rm -rf "$CERT_DIR"
mkdir -p "$CERT_DIR"

# --- CA ---
openssl req -new -x509 -nodes \
  -days "$DAYS" \
  -keyout "$CERT_DIR/ca-key.pem" \
  -out "$CERT_DIR/ca.pem" \
  -subj "/CN=ElixirTAK Dev CA"

# --- Server ---
openssl req -new -nodes \
  -keyout "$CERT_DIR/server-key.pem" \
  -out "$CERT_DIR/server.csr" \
  -subj "/CN=localhost"

cat > "$CERT_DIR/server-ext.cnf" <<EOF
subjectAltName = DNS:localhost, IP:127.0.0.1
EOF

openssl x509 -req \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.pem" \
  -CAkey "$CERT_DIR/ca-key.pem" \
  -CAcreateserial \
  -days "$DAYS" \
  -extfile "$CERT_DIR/server-ext.cnf" \
  -out "$CERT_DIR/server.pem"

# --- Client ---
openssl req -new -nodes \
  -keyout "$CERT_DIR/client-key.pem" \
  -out "$CERT_DIR/client.csr" \
  -subj "/CN=tak-dev-client"

openssl x509 -req \
  -in "$CERT_DIR/client.csr" \
  -CA "$CERT_DIR/ca.pem" \
  -CAkey "$CERT_DIR/ca-key.pem" \
  -CAcreateserial \
  -days "$DAYS" \
  -out "$CERT_DIR/client.pem"

# --- PKCS12 bundle for ATAK import ---
openssl pkcs12 -export \
  -in "$CERT_DIR/client.pem" \
  -inkey "$CERT_DIR/client-key.pem" \
  -certfile "$CERT_DIR/ca.pem" \
  -out "$CERT_DIR/client.p12" \
  -passout pass:atakonline

# --- Truststore (CA cert for clients to verify server) ---
cp "$CERT_DIR/ca.pem" "$CERT_DIR/truststore.pem"

# --- Cleanup temp files ---
rm -f "$CERT_DIR"/*.csr "$CERT_DIR"/*.cnf "$CERT_DIR"/*.srl

echo "Done. Certificates generated in $CERT_DIR"
ls -la "$CERT_DIR"
