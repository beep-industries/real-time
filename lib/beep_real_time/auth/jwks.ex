defmodule BeepRealTime.Auth.JWKS do
  use JokenJwks.DefaultStrategyTemplate
  require Logger

  def init_opts(opts) do
    url = jwks_url()

    Logger.info("Initializing JWKS fetcher with URL: #{url}")

    opts
    |> Keyword.put(:jwks_url, url)
    |> Keyword.put_new(:first_fetch_sync, true)  # Fetch synchronously on startup
    |> Keyword.put_new(:time_interval, 60_000)
    |> Keyword.put_new(:http_max_retries_per_fetch, 3)
    |> Keyword.put_new(:http_delay_per_retry, 1000)
  end

  defp jwks_url do
    base = Application.fetch_env!(:beep_real_time, :keycloak_url)
    realm = Application.fetch_env!(:beep_real_time, :keycloak_realm)
    url = "#{base}/realms/#{realm}/protocol/openid-connect/certs"
    Logger.info("JWKS URL: #{url}")
    url
  end
end
