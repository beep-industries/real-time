# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :beep_real_time,
  generators: [timestamp_type: :utc_datetime]

# OIDC Authentication Configuration
# Defaults for development - overridden in runtime.exs for production
config :beep_real_time,
  keycloak_url: "http://localhost:8080",
  keycloak_realm: "myrealm"

# Configures the endpoint
config :beep_real_time, BeepRealTimeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BeepRealTimeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BeepRealTime.PubSub,
  live_view: [signing_salt: "S8BBz2u1"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :beep_real_time, BeepRealTime.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Tesla to use Hackney adapter for HTTP requests (used by JokenJwks)
config :tesla, adapter: Tesla.Adapter.Hackney

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
