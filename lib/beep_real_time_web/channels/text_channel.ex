defmodule BeepRealTimeWeb.TextChannel do
  use Phoenix.Channel
  alias BeepRealTimeWeb.ChannelAuth

  # A user connects to this channel to receive real-time updates about messages posted in the text channel identified by id.
  @impl true
  def join("text-channel:" <> _id, _params, socket) do
    # Require user to be connected to UserChannel first
    case ChannelAuth.require_user_channel(socket) do
      :ok ->
        # TODO: Authorize that the user can access this text channel
        {:ok, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
