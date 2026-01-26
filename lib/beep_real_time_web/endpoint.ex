defmodule BeepRealTimeWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :beep_real_time

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_beep_real_time_key",
    signing_salt: "s5xlp9T7",
    same_site: "Lax"
  ]

  # Primary WebSocket for real-time signaling
  socket "/socket", BeepRealTimeWeb.UserSocket,
    websocket: [timeout: 60_000, check_origin: false],
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :beep_real_time,
    gzip: false,
    only: BeepRealTimeWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug BeepRealTimeWeb.Router
end
