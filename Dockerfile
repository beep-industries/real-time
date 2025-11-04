# Simple development Dockerfile for BeepRealTime (Phoenix)
# Multi-stage build to cache deps and build the app

FROM elixir:1.14.5 AS base

# Set up workdir
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
  && rm -rf /var/lib/apt/lists/*

# Pre-install Hex/Rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files and fetch deps first (better layer caching)
COPY mix.exs .
COPY config ./config

RUN mix deps.get --only prod || true \
 && mix deps.get

# Copy the rest of the source
COPY . .

# Expose the Phoenix port
EXPOSE 4000

# Default environment for running the server in a container
ENV MIX_ENV=dev \
    PORT=4000 \
    PHX_SERVER=true

# Start the Phoenix endpoint
CMD ["bash", "-lc", "mix phx.server"]
