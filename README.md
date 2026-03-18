# ElixirTAK

A TAK (Team Awareness Kit) server written in Elixir, with a real-time web
dashboard for shared situational awareness. Handles the CoT (Cursor on Target)
protocol over TCP and TLS, relays position reports and chat between connected
ATAK/iTAK clients, and provides a browser-based Common Operating Picture built
with React and CesiumJS.

## Features

- **CoT protocol support** - XML and TAK Protocol (protobuf) over TCP and mutual TLS
- **Real-time dashboard** - React + CesiumJS 3D globe with live position tracking, chat, and event feed
- **SA caching** - new clients receive the latest known positions on connect
- **Group routing** - clients are isolated by group, with broadcast types (chat, emergency) crossing boundaries
- **Data packages** - ATAK-compatible upload/download API (`/Marti/sync/*`)
- **Federation** - multi-server event relay over distributed Erlang (NATS transport planned)
- **Certificate management** - Mix tasks for CA setup, client cert generation, and revocation
- **SQLite persistence** - event history with configurable retention
- **Dev simulator** - 6 fake clients with movement patterns for testing without real devices

## Requirements

- Elixir ~> 1.18 (OTP 27+)
- Node.js + pnpm (for building the dashboard)

## Quick Start

```bash
# Clone and install dependencies
git clone https://github.com/bmullis/elixir_tak.git
cd elixir_tak
mix deps.get
mix ecto.setup
cd assets && pnpm install && cd ..

# Generate dev TLS certificates
bash scripts/gen_dev_certs.sh

# Build the dashboard
mix dashboard.build

# Start the server
mix phx.server
```

The dashboard is available at **http://localhost:8443/dashboard**.

In dev mode, 6 simulated clients will appear on the map automatically.

### Connecting TAK Clients

| Port | Protocol | Use case |
|------|----------|----------|
| 8087 | TCP | Plaintext CoT (dev/testing) |
| 8089 | TLS | Mutual TLS (production, required by iTAK) |
| 8443 | HTTP | Web dashboard and data package API |

**ATAK/iTAK:** Generate a connection profile to import directly into the app:

```bash
mix elixir_tak.gen_profile --cn "YourCallsign" --host YOUR_IP
```

This creates a `.zip` file with certs and server config that can be imported via
the TAK client's settings.

## Configuration

ElixirTAK is configured through `config/*.exs` files in development and
environment variables in production:

| Variable | Default | Description |
|----------|---------|-------------|
| `TAK_TCP_PORT` | 8087 | CoT plaintext TCP port |
| `TAK_TLS_PORT` | 8089 | CoT mutual TLS port |
| `TAK_TLS_ENABLED` | true | Enable/disable TLS listener |
| `TAK_HTTP_PORT` | 8080 | HTTP port |
| `TAK_HTTPS_PORT` | 8443 | HTTPS port |
| `TAK_CERTFILE` | - | Server TLS certificate path |
| `TAK_KEYFILE` | - | Server TLS private key path |
| `TAK_CACERTFILE` | - | CA certificate path |
| `SECRET_KEY_BASE` | - | Phoenix session signing key (required in prod) |
| `FEDERATION_ENABLED` | false | Enable multi-server federation |
| `FEDERATION_TRANSPORT` | beam | Federation transport (`beam` or `nats`) |
| `FEDERATION_PEERS` | - | Comma-separated Erlang node names |

## Certificate Management

ElixirTAK includes Mix tasks for managing a simple CA:

```bash
# Initialize a Certificate Authority
mix elixir_tak.init_ca

# Generate a server certificate
mix elixir_tak.gen_server_cert

# Generate a client certificate
mix elixir_tak.gen_client_cert --cn "Operator1"

# Generate an importable connection profile
mix elixir_tak.gen_profile --cn "Operator1" --host 192.168.1.100

# Revoke a client certificate
mix elixir_tak.revoke_cert --serial 1234
```

For development, the `scripts/gen_dev_certs.sh` script generates all necessary
certs in one step.

## Testing

```bash
# Run the test suite
mix test

# Run the end-to-end smoke test (starts its own TCP clients)
mix smoke

# Federation tests (requires distributed Erlang)
mix test --include federation --sname test_node
```

## Architecture

ElixirTAK is a single-node OTP application. All runtime state lives in ETS
tables supervised by a `one_for_one` supervision tree. There is no external
database dependency beyond an optional SQLite file for event history.

```
TAK Client --> TCP/TLS --> CotHandler
  --> CotFramer (byte stream --> complete XML/protobuf messages)
  --> CotParser/ProtoParser --> %CotEvent{}
  --> PubSub broadcast
  --> SACache / ChatCache / History
  --> All other connected handlers relay to their clients
  --> Dashboard receives updates via Phoenix Channel
```

Key design decisions:

- **CotEvent struct is the lingua franca.** Parsing happens at ingress,
  encoding at egress. Everything internal works with structs.
- **raw_detail passthrough.** The server preserves XML detail elements it
  doesn't understand, so vendor-specific extensions survive relay.
- **Receiver-side group filtering.** Every event broadcasts globally. Each
  handler decides whether to deliver based on group membership.
- **No protoc dependency.** Protobuf support uses hand-written encoder/decoder
  modules, keeping the build simple.

## Project Structure

```
lib/
  elixir_tak/
    protocol/       # CotParser, CotEncoder, CotFramer, CotValidator, CotEvent
    transport/      # CotHandler (ThousandIsland TCP/TLS handler)
    proto/          # Protobuf parser, encoder, negotiation
    federation/     # Multi-server relay (Manager, Transport, Policy)
    dev/            # Simulator for fake clients
  elixir_tak_web/   # Phoenix endpoint, channels, controllers
  mix/tasks/        # Certificate and profile generation tasks
assets/             # React + Vite + TypeScript dashboard
priv/static/        # Built dashboard assets
config/             # Application configuration
scripts/            # Dev cert generation, smoke test
```

## Deployment

### Docker Compose (recommended)

```bash
docker compose up -d
```

That's it. On first run the container will:
- Generate a secret key (persisted in the data volume)
- Generate self-signed TLS certificates
- Run database migrations
- Start all listeners (TCP, TLS, HTTP, HTTPS)

Dashboard: **http://localhost:8080/dashboard**

Data and certs are persisted in named Docker volumes (`tak_data`, `tak_certs`)
automatically. To use your own certificates, copy them into the certs volume
(`server.pem`, `server-key.pem`, `ca.pem`) before starting the container.

Optional environment variables can be set in `docker-compose.yml`:

```yaml
environment:
  - PHX_HOST=your.domain.com
  - SECRET_KEY_BASE=your_secret    # auto-generated if not set
  - TAK_CERT_PASSWORD=atakonline
```

### Standalone release

If you prefer to run without Docker:

```bash
# Build the dashboard
cd assets && pnpm install && pnpm build && cd ..

# Build the release
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release

# Run it (SECRET_KEY_BASE is required)
SECRET_KEY_BASE=$(mix phx.gen.secret) \
  _build/prod/rel/elixir_tak/bin/elixir_tak start
```

The release is a standalone directory that can be copied to any machine with the
same OS/architecture. No Elixir or Erlang installation required on the target.
Database migrations run automatically on startup.

## License

MIT License. See [LICENSE](LICENSE) for details.
