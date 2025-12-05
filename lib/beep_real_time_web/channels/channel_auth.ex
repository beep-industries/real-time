defmodule BeepRealTimeWeb.ChannelAuth do
  @moduledoc """
  Helper module for channel authorization.
  Ensures users are connected to UserChannel before joining other channels.
  """

  alias BeepRealTimeWeb.Presence
  require Logger

  @doc """
  Checks if the user is present in their UserChannel.
  Returns :ok if present, {:error, reason} otherwise.
  """
  def require_user_channel(socket) do
    user_id = socket.assigns[:user_id]

    Logger.info("Checking presence content: #{inspect(Presence.list("user:#{user_id}"))}")
    if user_id do
      case Presence.get_by_key("user:#{user_id}", user_id) do
        %{metas: [_ | _]} ->
          :ok

        _ ->
          {:error, %{reason: "must_join_user_channel_first"}}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
end

