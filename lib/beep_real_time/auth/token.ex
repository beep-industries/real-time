defmodule BeepRealTime.Auth.KeycloakToken do
  use Joken.Config

  add_hook(JokenJwks, strategy: BeepRealTime.Auth.JWKS)

  @impl true
  def token_config do
    iss =
      "#{Application.fetch_env!(:beep_real_time, :keycloak_url)}/realms/" <>
      Application.fetch_env!(:beep_real_time, :keycloak_realm)

    default_claims(skip: [:aud])
    |> add_claim("iss", nil, &(&1 == iss))
  end
end
