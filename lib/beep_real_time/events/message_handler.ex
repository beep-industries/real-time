defmodule BeepRealTime.Events.MessageHandler do
  @moduledoc """
  Handles message events by broadcasting them to connected clients via Phoenix PubSub.

  Each event type is broadcast to appropriate topics:
  - CreateMessageEvent: broadcast to `text-channel:{channel_id}` and `user:{id}` for notify_entries
  - UpdateMessageEvent: broadcast to `message:{message_id}` and `user:{id}` for notify_entries
  - DeleteMessageEvent: broadcast to `message:{message_id}`

  The exchange parameter is used to determine routing logic based on the origin exchange.
  """

  require Logger

  alias Messages.Events.{
    CreateMessageEvent,
    UpdateMessageEvent,
    DeleteMessageEvent
  }

  @doc """
  Handles message events by broadcasting them to appropriate PubSub topics.

  - CreateMessageEvent: broadcasts to `text-channel:{channel_id}` and `user:{id}` for mentions
  - UpdateMessageEvent: broadcasts to `message:{message_id}` and `user:{id}` for mentions
  - DeleteMessageEvent: broadcasts to `message:{message_id}`

  The exchange parameter indicates the origin exchange (e.g., "messages.events").
  """
  @spec handle(
          CreateMessageEvent.t() | UpdateMessageEvent.t() | DeleteMessageEvent.t() | term(),
          String.t() | nil
        ) ::
          :ok
  def handle(%CreateMessageEvent{} = event, exchange) do
    # Broadcast to the channel topic (using text-channel: prefix per guidelines)
    channel_topic = "text-channel:#{event.channel_id}"

    payload = %{
      event: "message.created",
      data: %{
        message_id: event.message_id,
        channel_id: event.channel_id,
        author_id: event.author_id,
        content: event.content || "",
        reply_to_message_id: event.reply_to_message_id || nil,
        attachments: format_attachments(event.attachments || []),
        notify_entries: format_notify_entries(event.notify_entries || [])
      }
    }

    Phoenix.PubSub.broadcast(BeepRealTime.PubSub, channel_topic, payload)

    Logger.info("Broadcasted message.created to #{channel_topic}",
      message_id: event.message_id,
      exchange: exchange
    )

    # Broadcast to user topics for notify_entries (mentions, etc.)
    broadcast_to_notify_entries(event.notify_entries || [], payload, exchange)

    :ok
  end

  def handle(%UpdateMessageEvent{} = event, exchange) do
    message_topic = "text-channel:#{event.channel_id}"

    payload = %{
      event: "message.updated",
      data: %{
        message_id: event.message_id,
        content: event.content || "",
        is_pinned: event.is_pinned,
        notify_entries: format_notify_entries(event.notify_entries || [])
      }
    }

    Phoenix.PubSub.broadcast(BeepRealTime.PubSub, message_topic, payload)

    Logger.info("Broadcasted message.updated to #{message_topic}",
      message_id: event.message_id,
      exchange: exchange
    )

    # Broadcast to user topics for notify_entries (mentions, etc.)
    broadcast_to_notify_entries(event.notify_entries || [], payload, exchange)

    :ok
  end

  def handle(%DeleteMessageEvent{} = event, exchange) do
    message_topic = "text-channel:#{event.channel_id}"

    payload = %{
      event: "message.deleted",
      data: %{
        message_id: event.message_id
      }
    }

    Phoenix.PubSub.broadcast(BeepRealTime.PubSub, message_topic, payload)

    Logger.info("Broadcasted message.deleted to #{message_topic}",
      message_id: event.message_id,
      exchange: exchange
    )

    :ok
  end

  # Handles unknown event types
  def handle(event, _exchange) do
    Logger.warning("Received unknown event type", event: inspect(event))
    :ok
  end

  # Backward compatibility: handle without exchange parameter
  def handle(event) do
    handle(event, nil)
  end

  ## Private helpers

  defp format_attachments(attachments) when is_list(attachments) do
    Enum.map(attachments, fn att ->
      %{
        id: att.id || "",
        name: att.name || "",
        url: att.url || ""
      }
    end)
  end

  defp format_attachments(_), do: []

  defp format_notify_entries(notify_entries) when is_list(notify_entries) do
    Enum.map(notify_entries, fn entry ->
      %{
        type: entry.type || "",
        id: entry.id || ""
      }
    end)
  end

  defp format_notify_entries(_), do: []

  # Broadcast notifications to user topics based on notify_entries
  defp broadcast_to_notify_entries(notify_entries, payload, exchange)
       when is_list(notify_entries) do
    Enum.each(notify_entries, fn entry ->
      case entry.type do
        "user" when is_binary(entry.id) and entry.id != "" ->
          user_topic = "user:#{entry.id}"
          Phoenix.PubSub.broadcast(BeepRealTime.PubSub, user_topic, payload)

          Logger.debug("Broadcasted notification to #{user_topic}",
            notify_entry_type: entry.type,
            exchange: exchange
          )

        "role" when is_binary(entry.id) and entry.id != "" ->
          # For role-based notifications, we might need to resolve role members
          # For now, log it - this could be extended to broadcast to all users with that role
          Logger.debug("Role-based notification detected",
            role_id: entry.id,
            exchange: exchange
          )

        _ ->
          Logger.debug("Unknown notify_entry type or missing id",
            type: entry.type,
            id: entry.id,
            exchange: exchange
          )
      end
    end)
  end

  defp broadcast_to_notify_entries(_, _, _), do: :ok
end
