# Production Dockerfile for BeepRealTime (Phoenix)
# Multi-stage build: builder -> runner

FROM elixir:1.19.2 AS builder

# Set up workdir
WORKDIR /app

# Set build ENV
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create app directory
WORKDIR /app

# Copy mix files and lock
COPY mix.exs mix.lock ./

# Copy config files
COPY config config

# Install and compile dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv

# Compile the application
RUN mix compile

# Build the release
RUN mix release

# Stage 2: Create the runtime image
FROM elixir:1.19.2 AS runner

# Set working directory
WORKDIR /app

# Copy the release from builder
COPY --from=builder --chown=app:app /app/_build/prod/rel/beep_real_time ./

# Expose the Phoenix port
EXPOSE 4000

# Set environment variables
ENV HOME=/app \
    PORT=4000 \
    MIX_ENV=prod

# Start the application using the release
CMD ["/app/bin/beep_real_time", "start"]
