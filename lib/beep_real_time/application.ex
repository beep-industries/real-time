defmodule BeepRealTime.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379/0"

    children = [
      BeepRealTimeWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:beep_real_time, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BeepRealTime.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: BeepRealTime.Finch},
      # gRPC client supervisor required by grpc library for client channels
      {GRPC.Client.Supervisor, []},
      # Redis connection used by deduper and other components
      {Redix, {redis_url, [name: BeepRealTime.Redis]}},
      # Real-time signaling deduper (idempotency)
      BeepRealTime.Signaling.Deduper,
      # RabbitMQ notification consumer
      BeepRealTime.Queue.Consumer,
      # Start to serve requests, typically the last entry
      BeepRealTimeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BeepRealTime.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeepRealTimeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
