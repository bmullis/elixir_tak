#!/bin/bash
set -e

CERT_DIR="${TAK_CERT_DIR:-/app/certs}"
DATA_DIR="${TAK_DATA_DIR:-/app/data}"

# Generate SECRET_KEY_BASE if not provided
if [ -z "$SECRET_KEY_BASE" ]; then
  if [ -f "$DATA_DIR/.secret_key_base" ]; then
    export SECRET_KEY_BASE=$(cat "$DATA_DIR/.secret_key_base")
  else
    export SECRET_KEY_BASE=$(openssl rand -hex 64)
    echo "$SECRET_KEY_BASE" > "$DATA_DIR/.secret_key_base"
    echo "Generated SECRET_KEY_BASE (saved to $DATA_DIR/.secret_key_base)"
  fi
fi

# Generate self-signed certs if none exist
if [ ! -f "$CERT_DIR/server.pem" ] || [ ! -f "$CERT_DIR/server-key.pem" ]; then
  echo "No TLS certificates found, generating self-signed certs..."

  # CA
  openssl req -new -x509 -nodes \
    -days 3650 \
    -keyout "$CERT_DIR/ca-key.pem" \
    -out "$CERT_DIR/ca.pem" \
    -subj "/CN=ElixirTAK CA" 2>/dev/null

  # Server cert
  openssl req -new -nodes \
    -keyout "$CERT_DIR/server-key.pem" \
    -out "$CERT_DIR/server.csr" \
    -subj "/CN=elixir-tak" 2>/dev/null

  openssl x509 -req \
    -in "$CERT_DIR/server.csr" \
    -CA "$CERT_DIR/ca.pem" \
    -CAkey "$CERT_DIR/ca-key.pem" \
    -CAcreateserial \
    -days 3650 \
    -out "$CERT_DIR/server.pem" 2>/dev/null

  rm -f "$CERT_DIR"/*.csr "$CERT_DIR"/*.srl
  echo "Self-signed certificates generated in $CERT_DIR"
fi

# Set cert paths if not explicitly configured
export TAK_CERTFILE="${TAK_CERTFILE:-$CERT_DIR/server.pem}"
export TAK_KEYFILE="${TAK_KEYFILE:-$CERT_DIR/server-key.pem}"
export TAK_CACERTFILE="${TAK_CACERTFILE:-$CERT_DIR/ca.pem}"

exec bin/elixir_tak start
