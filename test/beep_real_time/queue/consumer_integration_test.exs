defmodule BeepRealTime.Queue.ConsumerIntegrationTest do
  @moduledoc """
  Integration tests for RabbitMQ Consumer.

  These tests require a running RabbitMQ instance.
  Start it with: docker-compose -f docker-compose.rabbitmq.yml up -d
  """

  use ExUnit.Case, async: false

  alias BeepRealTime.RabbitMQCase
  alias Messages.Events.{CreateMessageEvent, NotifyEntry}

  setup do
    # Subscribe to PubSub topics for testing
    test_channel = "test_channel_#{System.unique_integer([:positive])}"
    test_user = "test_user_#{System.unique_integer([:positive])}"

    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "text-channel:#{test_channel}")
    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "user:#{test_user}")

    # Start a test consumer
    {consumer_pid, queue_name} = RabbitMQCase.start_test_consumer()

    on_exit(fn ->
      RabbitMQCase.stop_test_consumer(consumer_pid)
    end)

    %{
      consumer_pid: consumer_pid,
      queue_name: queue_name,
      test_channel: test_channel,
      test_user: test_user
    }
  end

  @tag :integration
  test "consumes CreateMessageEvent from queue and broadcasts to channel topic", %{
    queue_name: queue_name,
    test_channel: test_channel
  } do
    # Create a test event
    event = %CreateMessageEvent{
      message_id: "msg_#{System.unique_integer([:positive])}",
      channel_id: test_channel,
      author_id: "author_123",
      content: "Test message content",
      reply_to_message_id: nil,
      attachments: [],
      notify_entries: []
    }

    # Publish to queue
    assert :ok =
             RabbitMQCase.publish_protobuf_message(
               queue_name,
               event,
               "messages.create",
               "messages.events"
             )

    # Wait for message to be consumed and broadcast
    assert_receive %{
                     event: "message.created",
                     data: %{
                       message_id: message_id,
                       channel_id: ^test_channel,
                       author_id: "author_123",
                       content: "Test message content"
                     }
                   },
                   5000

    assert message_id == event.message_id
  end

  @tag :integration
  test "consumes CreateMessageEvent with notify_entries and broadcasts to both channel and user topics",
       %{
         queue_name: queue_name,
         test_channel: test_channel,
         test_user: test_user
       } do
    # Create a test event with notify_entries
    notify_entry = %NotifyEntry{
      type: "user",
      id: test_user
    }

    event = %CreateMessageEvent{
      message_id: "msg_#{System.unique_integer([:positive])}",
      channel_id: test_channel,
      author_id: "author_123",
      content: "Test message with mention @#{test_user}",
      reply_to_message_id: nil,
      attachments: [],
      notify_entries: [notify_entry]
    }

    # Publish to queue
    assert :ok =
             RabbitMQCase.publish_protobuf_message(
               queue_name,
               event,
               "messages.create",
               "messages.events"
             )

    # Give a moment for the message to be consumed
    Process.sleep(100)

    # Should receive on channel topic
    assert_receive %{
                     event: "message.created",
                     data: %{
                       message_id: message_id,
                       channel_id: ^test_channel,
                       notify_entries: [%{type: "user", id: ^test_user}]
                     }
                   },
                   5000

    # Should also receive on user topic for the mention
    assert_receive %{
                     event: "message.created",
                     data: %{
                       message_id: ^message_id,
                       notify_entries: [%{type: "user", id: ^test_user}]
                     }
                   },
                   5000
  end

  @tag :integration
  test "consumer status returns connected after successful connection", %{
    consumer_pid: consumer_pid,
    queue_name: queue_name
  } do
    # Check status via GenServer call directly
    {status, info} = GenServer.call(consumer_pid, {:status, queue_name}, 1000)

    assert status == true
    assert is_map(info)
    # Queue name should start with "test_notification_"
    assert String.starts_with?(queue_name, "test_notification_")
  end
end
