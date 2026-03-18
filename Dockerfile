# Build stage
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.9
ARG DEBIAN_VERSION=bookworm-20260223-slim
ARG NODE_VERSION=22

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# --- Build Elixir release ---
FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js + pnpm for dashboard build
ARG NODE_VERSION
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm

WORKDIR /app

# Install Elixir deps
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/prod.exs config/${MIX_ENV}.exs config/
COPY config/runtime.exs config/

RUN mix deps.compile

# Build dashboard assets
# Phoenix JS client is referenced as file:../deps/phoenix in package.json,
# which is satisfied by mix deps.get above
COPY assets/package.json assets/pnpm-lock.yaml assets/
RUN cd assets && pnpm install --frozen-lockfile

COPY assets assets
RUN cd assets && pnpm build

# Compile and build release
COPY priv priv
COPY lib lib
RUN mix compile
RUN mix phx.digest
RUN mix release

# --- Runtime image ---
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN useradd --create-home --shell /bin/bash app

# Create data and certs directories
RUN mkdir -p /app/data /app/certs && chown -R app:app /app

COPY --from=build --chown=app:app /app/_build/prod/rel/elixir_tak ./
COPY --chown=app:app scripts/docker-entrypoint.sh ./

USER app

# TCP (CoT plaintext), TLS (CoT mutual TLS), HTTP (dashboard + API)
EXPOSE 8087 8089 8080 8443

# Volumes for persistent data and certificates
VOLUME ["/app/data", "/app/certs"]

ENV PHX_SERVER=true

ENTRYPOINT ["./docker-entrypoint.sh"]
