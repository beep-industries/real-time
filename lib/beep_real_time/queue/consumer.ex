defmodule BeepRealTime.Queue.Consumer do
  @moduledoc """
  RabbitMQ consumer responsible for ingesting notifications from the
  `notification` queue and forwarding them to the dispatcher.

  The consumer keeps a persistent connection to RabbitMQ, automatically
  reconnecting with exponential backoff whenever the connection or channel is
  lost. Messages are acknowledged only after a successful dispatch.
  """

  use GenServer
  use AMQP

  require Logger

  alias BeepRealTime.Signaling.Dispatcher
  alias BeepRealTime.Events.{MessageDecoder, MessageHandler}

  @default_queue "notification"
  @default_prefetch 32
  @default_backoff 5000

  @type status_info :: {boolean(), map()}

  @doc """
  Starts the consumer process under a supervisor.
  """
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Returns the connection status for the given queue.
  """
  @spec status(String.t()) :: status_info()
  def status(queue \\ @default_queue) do
    case Process.whereis(__MODULE__) do
      nil -> {false, %{reason: :not_started}}
      pid -> GenServer.call(pid, {:status, queue})
    end
  catch
    :exit, reason -> {false, %{reason: reason}}
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    config = Application.get_env(:beep_real_time, __MODULE__, [])

    state = %{
      url:
        Keyword.get(opts, :url) || Keyword.get(config, :url) || System.get_env("RABBITMQ_URL") ||
          "amqp://guest:guest@localhost:5672",
      queue: Keyword.get(opts, :queue) || Keyword.get(config, :queue) || @default_queue,
      prefetch:
        Keyword.get(opts, :prefetch_count) || Keyword.get(config, :prefetch_count) ||
          @default_prefetch,
      backoff: Keyword.get(opts, :backoff) || Keyword.get(config, :backoff) || @default_backoff,
      connection: nil,
      connection_monitor: nil,
      channel: nil,
      channel_monitor: nil,
      consumer_tag: nil,
      reconnect_timer: nil,
      status: :disconnected,
      last_error: :not_connected
    }

    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_call({:status, queue}, _from, %{queue: queue, status: :connected} = state) do
    {:reply, {true, %{}}, state}
  end

  def handle_call({:status, queue}, _from, %{queue: queue} = state) do
    {:reply, {false, %{reason: state.last_error}}, state}
  end

  def handle_call({:status, _queue}, _from, state) do
    {:reply, {false, %{reason: :unknown_queue}}, state}
  end

  @impl true
  def handle_info(:connect, %{reconnect_timer: _ref} = state) do
    state = %{state | reconnect_timer: nil}

    case establish(state) do
      {:ok, new_state} ->
        Logger.info("Queue consumer connected to RabbitMQ", queue: new_state.queue)
        {:noreply, new_state}

      {:error, reason, new_state} ->
        Logger.warning("Queue consumer failed to connect",
          reason: inspect(reason),
          queue: new_state.queue
        )

        {:noreply, schedule_reconnect(new_state)}
    end
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: tag}}, state) do
    {:noreply, %{state | consumer_tag: tag}}
  end

  def handle_info({:basic_consume_ok, tag}, state) when is_binary(tag) do
    {:noreply, %{state | consumer_tag: tag}}
  end

  def handle_info({:basic_cancel, %{consumer_tag: tag}}, state) do
    Logger.warning("Queue consumer cancelled by broker", consumer_tag: tag)
    {:noreply, schedule_reconnect(cleanup(state))}
  end

  def handle_info({:basic_cancel, tag}, state) when is_binary(tag) do
    Logger.warning("Queue consumer cancelled by broker", consumer_tag: tag)
    {:noreply, schedule_reconnect(cleanup(state))}
  end

  def handle_info({:basic_cancel_ok, _meta}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta}, %{channel: channel} = state)
      when not is_nil(channel) do
    exchange = get_exchange(meta)

    result =
      with event_type <- get_event_type(meta),
           {:ok, decoded_event} <- decode_protobuf(payload, event_type),
           :ok <- handle_message_event(decoded_event, exchange) do
        ack(channel, meta.delivery_tag)
        :ok
      else
        {:error, reason} ->
          Logger.error("Failed to process queue message",
            reason: inspect(reason),
            event_type: get_event_type(meta),
            exchange: exchange,
            queue: state.queue
          )

          # Try fallback to JSON dispatch for backward compatibility
          case decode_json(payload) do
            {:ok, json_event} ->
              case dispatch(json_event) do
                :ok ->
                  ack(channel, meta.delivery_tag)
                  :ok

                {:error, _} ->
                  reject(channel, meta.delivery_tag, reason)
                  {:error, reason}
              end

            _ ->
              reject(channel, meta.delivery_tag, reason)
              {:error, reason}
          end
      end

    if match?({:error, _}, result) do
      :telemetry.execute([:beep_real_time, :queue, :error], %{count: 1}, %{queue: state.queue})
    else
      :telemetry.execute([:beep_real_time, :queue, :consume], %{count: 1}, %{queue: state.queue})
    end

    {:noreply, state}
  rescue
    exception ->
      Logger.error("Unhandled exception while processing message",
        exception: Exception.message(exception),
        queue: state.queue
      )

      reject(channel, meta.delivery_tag, {:exception, exception})
      {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    cond do
      state.channel_monitor == ref ->
        Logger.warning("Queue channel terminated", reason: inspect(reason))

        state
        |> cleanup()
        |> Map.put(:last_error, {:channel_down, reason})
        |> schedule_reconnect()
        |> noreply()

      state.connection_monitor == ref ->
        Logger.warning("Queue connection terminated", reason: inspect(reason))

        state
        |> cleanup()
        |> Map.put(:last_error, {:connection_down, reason})
        |> schedule_reconnect()
        |> noreply()

      true ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup(state)
    :ok
  end

  ## Helpers

  defp establish(state) do
    with {:ok, connection} <- Connection.open(state.url),
         {:ok, channel} <- Channel.open(connection),
         :ok <- Basic.qos(channel, prefetch_count: state.prefetch),
         {:ok, _} <- Queue.declare(channel, state.queue, durable: true),
         {:ok, tag} <- consume(channel, state.queue) do
      conn_ref = Process.monitor(connection.pid)
      chan_ref = Process.monitor(channel.pid)

      {:ok,
       %{
         state
         | connection: connection,
           connection_monitor: conn_ref,
           channel: channel,
           channel_monitor: chan_ref,
           consumer_tag: tag,
           status: :connected,
           last_error: nil
       }}
    else
      {:error, reason} ->
        {:error, reason,
         %{cleanup(state) | last_error: normalize_reason(reason), status: :disconnected}}
    end
  end

  defp consume(channel, queue) do
    case Basic.consume(channel, queue) do
      {:ok, %{consumer_tag: tag}} -> {:ok, tag}
      {:ok, tag} when is_binary(tag) -> {:ok, tag}
      other -> other
    end
  end

  # Extract event type from RabbitMQ metadata (headers or routing_key)
  defp get_event_type(meta) do
    case meta.headers do
      nil ->
        parse_routing_key(meta.routing_key)

      headers ->
        case List.keyfind(headers, "event_type", 0) do
          {"event_type", :longstr, event_type} -> event_type
          {"event_type", :binary, event_type} -> event_type
          _ -> parse_routing_key(meta.routing_key)
        end
    end
  end

  defp parse_routing_key(nil), do: nil

  defp parse_routing_key(routing_key) when is_binary(routing_key) do
    # Example: "events.messages.create" -> "messages.create"
    # Or: "messages.create" -> "messages.create"
    case String.split(routing_key, ".") do
      ["events" | rest] -> Enum.join(rest, ".")
      parts -> Enum.join(parts, ".")
    end
  end

  defp parse_routing_key(_), do: nil

  # Extract exchange from RabbitMQ metadata
  defp get_exchange(meta) do
    case Map.get(meta, :exchange) do
      nil -> Map.get(meta, "exchange")
      exchange -> exchange
    end
  end

  # Decode Protobuf payload
  defp decode_protobuf(payload, event_type) when is_binary(payload) and is_binary(event_type) do
    MessageDecoder.decode(payload, event_type)
  end

  defp decode_protobuf(_payload, _event_type), do: {:error, :invalid_event_type}

  # Handle message events via MessageHandler
  defp handle_message_event(event, exchange) do
    MessageHandler.handle(event, exchange)
  end

  # Fallback: decode JSON payload (for backward compatibility)
  defp decode_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _other} -> {:error, :invalid_payload}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp decode_json(payload) when is_map(payload), do: {:ok, payload}
  defp decode_json(_), do: {:error, :invalid_payload}

  defp dispatch(event) do
    case safe_dispatch(event) do
      :ok -> :ok
      {:error, reason} -> {:error, {:dispatch_failed, reason}}
    end
  end

  defp safe_dispatch(event) do
    Dispatcher.consume(event)
  rescue
    exception ->
      Logger.error("Dispatcher raised while consuming event",
        exception: Exception.message(exception)
      )

      {:error, {:exception, exception}}
  end

  defp ack(channel, tag) do
    Basic.ack(channel, tag)
  rescue
    exception ->
      Logger.error("Failed to ack message", exception: Exception.message(exception))
      :ok
  end

  defp reject(channel, tag, reason) do
    Logger.debug("Rejecting message", reason: inspect(reason))
    Basic.reject(channel, tag, requeue: false)
  rescue
    exception ->
      Logger.error("Failed to reject message", exception: Exception.message(exception))
      :ok
  end

  defp cleanup(state) do
    maybe_close_channel(state.channel)
    maybe_close_connection(state.connection)

    flush_monitor(state.channel_monitor)
    flush_monitor(state.connection_monitor)

    %{
      state
      | channel: nil,
        channel_monitor: nil,
        connection: nil,
        connection_monitor: nil,
        consumer_tag: nil,
        status: :disconnected
    }
  end

  defp maybe_close_channel(nil), do: :ok

  defp maybe_close_channel(channel) do
    if Process.alive?(channel.pid) do
      Channel.close(channel)
    end
  rescue
    _ -> :ok
  end

  defp maybe_close_connection(nil), do: :ok

  defp maybe_close_connection(connection) do
    if Process.alive?(connection.pid) do
      Connection.close(connection)
    end
  rescue
    _ -> :ok
  end

  defp flush_monitor(nil), do: :ok

  defp flush_monitor(ref) do
    Process.demonitor(ref, [:flush])
  rescue
    _ -> :ok
  end

  defp schedule_reconnect(%{reconnect_timer: nil} = state) do
    ref = Process.send_after(self(), :connect, state.backoff)
    %{state | reconnect_timer: ref}
  end

  defp schedule_reconnect(state), do: state

  defp noreply(state), do: {:noreply, state}

  defp normalize_reason(%{reason: reason}), do: normalize_reason(reason)
  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason) when is_atom(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)
end
