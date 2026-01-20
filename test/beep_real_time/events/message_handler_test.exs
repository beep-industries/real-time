defmodule BeepRealTime.Events.MessageHandlerTest do
  use ExUnit.Case

  alias BeepRealTime.Events.MessageHandler

  alias Messages.Events.{
    CreateMessageEvent,
    UpdateMessageEvent,
    DeleteMessageEvent,
    NotifyEntry
  }

  setup do
    # Subscribe to PubSub topics for testing
    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "text-channel:test_channel")
    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "message:test_message")
    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "message:msg_123")
    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "user:user_789")
    Phoenix.PubSub.subscribe(BeepRealTime.PubSub, "user:user_999")

    :ok
  end

  describe "handle/1 CreateMessageEvent" do
    test "broadcasts message.created to channel topic" do
      event = %CreateMessageEvent{
        message_id: "msg_123",
        channel_id: "test_channel",
        author_id: "user_456",
        content: "Hello World",
        reply_to_message_id: nil,
        attachments: [],
        notify_entries: []
      }

      assert :ok = MessageHandler.handle(event, "messages.events")

      assert_receive %{
                       event: "message.created",
                       data: %{
                         message_id: "msg_123",
                         channel_id: "test_channel",
                         author_id: "user_456",
                         content: "Hello World",
                         reply_to_message_id: nil,
                         attachments: [],
                         notify_entries: []
                       }
                     },
                     1000
    end

    test "broadcasts message.created with attachments and notify_entries" do
      attachment = %CreateMessageEvent.Attachment{
        id: "att_1",
        name: "file.pdf",
        url: "https://example.com/file.pdf"
      }

      notify_entry = %NotifyEntry{
        type: "user",
        id: "user_789"
      }

      event = %CreateMessageEvent{
        message_id: "msg_456",
        channel_id: "test_channel",
        author_id: "user_456",
        content: "Check this out",
        reply_to_message_id: "msg_123",
        attachments: [attachment],
        notify_entries: [notify_entry]
      }

      assert :ok = MessageHandler.handle(event, "messages.events")

      # Should receive on channel topic
      assert_receive %{
                       event: "message.created",
                       data: %{
                         message_id: "msg_456",
                         attachments: [
                           %{id: "att_1", name: "file.pdf", url: "https://example.com/file.pdf"}
                         ],
                         notify_entries: [
                           %{type: "user", id: "user_789"}
                         ]
                       }
                     },
                     1000

      # Should also receive on user topic for the mention
      assert_receive %{
                       event: "message.created",
                       data: %{
                         message_id: "msg_456",
                         notify_entries: [
                           %{type: "user", id: "user_789"}
                         ]
                       }
                     },
                     1000
    end
  end

  describe "handle/1 UpdateMessageEvent" do
    test "broadcasts message.updated to message topic" do
      event = %UpdateMessageEvent{
        message_id: "test_message",
        content: "Updated content",
        is_pinned: true,
        notify_entries: []
      }

      assert :ok = MessageHandler.handle(event, "messages.events")

      assert_receive %{
                       event: "message.updated",
                       data: %{
                         message_id: "test_message",
                         content: "Updated content",
                         is_pinned: true,
                         notify_entries: []
                       }
                     },
                     1000
    end

    test "broadcasts message.updated with nil is_pinned" do
      event = %UpdateMessageEvent{
        message_id: "test_message",
        content: "Updated content",
        is_pinned: nil,
        notify_entries: []
      }

      assert :ok = MessageHandler.handle(event, "messages.events")

      assert_receive %{
                       event: "message.updated",
                       data: %{
                         message_id: "test_message",
                         is_pinned: nil
                       }
                     },
                     1000
    end
  end

  describe "handle/1 DeleteMessageEvent" do
    test "broadcasts message.deleted to message topic" do
      event = %DeleteMessageEvent{
        message_id: "test_message"
      }

      assert :ok = MessageHandler.handle(event, "messages.events")

      assert_receive %{
                       event: "message.deleted",
                       data: %{
                         message_id: "test_message"
                       }
                     },
                     1000
    end
  end

  describe "handle/1 UpdateMessageEvent with notify_entries" do
    test "broadcasts to both message topic and user topics for mentions" do
      notify_entry = %NotifyEntry{
        type: "user",
        id: "user_999"
      }

      event = %UpdateMessageEvent{
        message_id: "test_message",
        content: "Updated with mention",
        is_pinned: false,
        notify_entries: [notify_entry]
      }

      assert :ok = MessageHandler.handle(event, "messages.events")

      # Should receive on message topic
      assert_receive %{
                       event: "message.updated",
                       data: %{
                         message_id: "test_message",
                         content: "Updated with mention",
                         notify_entries: [%{type: "user", id: "user_999"}]
                       }
                     },
                     1000

      # Should also receive on user topic for the mention
      assert_receive %{
                       event: "message.updated",
                       data: %{
                         message_id: "test_message",
                         notify_entries: [%{type: "user", id: "user_999"}]
                       }
                     },
                     1000
    end
  end

  describe "handle/1 unknown event" do
    test "logs warning and returns :ok for unknown event types" do
      unknown_event = %{type: "unknown", data: "test"}

      assert :ok = MessageHandler.handle(unknown_event, "messages.events")
    end
  end
end
