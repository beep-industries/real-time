defmodule BeepRealTime.Events.MessageDecoder do
  @moduledoc """
  Decodes Protobuf binary payloads into Elixir structs based on event type.
  """

  require Logger

  alias Messages.Events.{
    CreateMessageEvent,
    UpdateMessageEvent,
    DeleteMessageEvent
  }

  @doc """
  Decodes a binary Protobuf payload into an Elixir struct based on the event type.

  ## Examples

      iex> MessageDecoder.decode(payload, "messages.create")
      {:ok, %CreateMessageEvent{}}

      iex> MessageDecoder.decode(payload, "messages.update")
      {:ok, %UpdateMessageEvent{}}

      iex> MessageDecoder.decode(payload, "messages.delete")
      {:ok, %DeleteMessageEvent{}}

      iex> MessageDecoder.decode(payload, "unknown.event")
      {:error, :unknown_event_type}
  """
  @spec decode(binary(), String.t()) ::
          {:ok, struct()} | {:error, :unknown_event_type | {:decode_failed, term()}}
  def decode(payload, event_type) when is_binary(payload) and is_binary(event_type) do
    try do
      case event_type do
        "messages.create" ->
          event = CreateMessageEvent.decode(payload)
          {:ok, event}

        "messages.update" ->
          event = UpdateMessageEvent.decode(payload)
          {:ok, event}

        "messages.delete" ->
          event = DeleteMessageEvent.decode(payload)
          {:ok, event}

        _ ->
          {:error, :unknown_event_type}
      end
    rescue
      e ->
        Logger.error("Failed to decode Protobuf payload",
          event_type: event_type,
          error: Exception.message(e)
        )

        {:error, {:decode_failed, e}}
    end
  end

  def decode(_payload, _event_type) do
    {:error, :invalid_payload}
  end
end
