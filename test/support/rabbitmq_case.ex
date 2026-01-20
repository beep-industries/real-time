defmodule BeepRealTime.RabbitMQCase do
  @moduledoc """
  Helper module for RabbitMQ integration tests.

  Provides utilities to:
  - Start/stop test consumers
  - Publish messages to queues
  - Wait for message consumption
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import BeepRealTime.RabbitMQCase
    end
  end

  @doc """
  Publishes a Protobuf message to a RabbitMQ queue.

  ## Examples

      iex> event = %CreateMessageEvent{message_id: "123", channel_id: "ch1", ...}
      iex> publish_protobuf_message("test_queue", event, "messages.create", "messages.events")
      :ok
  """
  def publish_protobuf_message(queue, event, routing_key, exchange \\ "") do
    url = System.get_env("RABBITMQ_URL") || "amqp://guest:guest@localhost:5672"

    with {:ok, connection} <- AMQP.Connection.open(url),
         {:ok, channel} <- AMQP.Channel.open(connection),
         {:ok, _queue_info} <- AMQP.Queue.declare(channel, queue, durable: true),
         :ok <- publish_with_headers(channel, queue, event, routing_key, exchange) do
      AMQP.Channel.close(channel)
      AMQP.Connection.close(connection)
      :ok
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp publish_with_headers(channel, queue, event, routing_key, _exchange) do
    # Encode the Protobuf event to binary
    payload = Protobuf.encode(event)

    # Create headers with event_type
    headers = [
      {"event_type", :longstr, routing_key}
    ]

    # Publish to queue (using default exchange)
    AMQP.Basic.publish(channel, "", queue, payload,
      headers: headers,
      persistent: true
    )
  end

  @doc """
  Starts a test consumer with a unique queue name.
  Returns the consumer pid and queue name.
  """
  def start_test_consumer(opts \\ []) do
    queue_name =
      Keyword.get(opts, :queue, "test_notification_#{System.unique_integer([:positive])}")

    url =
      Keyword.get(
        opts,
        :url,
        System.get_env("RABBITMQ_URL") || "amqp://guest:guest@localhost:5672"
      )

    consumer_opts = [
      name: Keyword.get(opts, :name, :"test_consumer_#{System.unique_integer([:positive])}"),
      queue: queue_name,
      url: url
    ]

    {:ok, pid} = BeepRealTime.Queue.Consumer.start_link(consumer_opts)

    # Wait for connection
    wait_for_connection(pid, queue_name, 10)

    {pid, queue_name}
  end

  @doc """
  Stops a test consumer.
  """
  def stop_test_consumer(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal)
    end
  end

  defp wait_for_connection(pid, queue, max_attempts) do
    wait_for_connection(pid, queue, max_attempts, 0)
  end

  defp wait_for_connection(_pid, _queue, max_attempts, attempts) when attempts >= max_attempts do
    {:error, :timeout}
  end

  defp wait_for_connection(pid, queue, max_attempts, attempts) do
    # Check if process is alive and try to get status
    if Process.alive?(pid) do
      # Give it a moment to connect
      Process.sleep(200)

      # Try to get status via GenServer call
      try do
        case GenServer.call(pid, {:status, queue}, 100) do
          {true, _} -> :ok
          _ -> wait_for_connection(pid, queue, max_attempts, attempts + 1)
        end
      catch
        :exit, _ -> wait_for_connection(pid, queue, max_attempts, attempts + 1)
      end
    else
      {:error, :process_dead}
    end
  end
end
