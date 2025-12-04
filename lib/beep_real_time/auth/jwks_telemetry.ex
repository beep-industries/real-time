defmodule BeepRealTime.Auth.JwksTelemetry do
  @moduledoc """
  Telemetry handler for JWKS events to help debug authentication issues.
  """
  require Logger

  def setup do
    :telemetry.attach_many(
      "jwks-telemetry-handler",
      [
        [:joken_jwks, :default_strategy, :refetch],
        [:joken_jwks, :default_strategy, :signers],
        [:joken_jwks, :http_fetcher, :start],
        [:joken_jwks, :http_fetcher, :stop],
        [:joken_jwks, :http_fetcher, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:joken_jwks, :default_strategy, :refetch], measurements, metadata, _config) do
    Logger.info("JWKS: Refetching signers for module #{inspect(metadata.module)}")
  end

  def handle_event([:joken_jwks, :default_strategy, :signers], measurements, metadata, _config) do
    signer_count = map_size(metadata.signers)
    Logger.info("JWKS: Successfully fetched #{signer_count} signer(s) for module #{inspect(metadata.module)}")
    Logger.debug("JWKS: Signer keys: #{inspect(Map.keys(metadata.signers))}")
  end

  def handle_event([:joken_jwks, :http_fetcher, :start], measurements, metadata, _config) do
    Logger.debug("JWKS: Starting HTTP fetch from #{metadata.url}")
  end

  def handle_event([:joken_jwks, :http_fetcher, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("JWKS: HTTP fetch completed in #{duration_ms}ms")
  end

  def handle_event([:joken_jwks, :http_fetcher, :exception], measurements, metadata, _config) do
    Logger.error("JWKS: HTTP fetch failed - #{inspect(metadata.kind)}: #{inspect(metadata.reason)}")
    Logger.error("JWKS: Stacktrace: #{inspect(metadata.stacktrace)}")
  end
end

