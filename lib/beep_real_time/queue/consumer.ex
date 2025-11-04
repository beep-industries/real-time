defmodule BeepRealTime.Queue.Consumer do
  @moduledoc """
  Queue consumer disabled.

  The project currently does not integrate with AMQP/RabbitMQ. This stub module
  is kept to preserve references and provide a stable API.

  - start_link/1 does nothing and returns :ignore
  - status/1 always returns {false, %{reason: :disabled}}
  """

  @doc """
  Start link is a no-op; supervisor can include it safely (but we don't).
  """
  def start_link(_opts), do: :ignore

  @doc """
  Always reports disabled status.
  """
  def status(_queue), do: {false, %{reason: :disabled}}
end
