defmodule BeepRealTimeWeb.ServerChannel do
  use Phoenix.Channel
  alias BeepRealTimeWeb.ChannelAuth

  # A user connects to this channel to receive notifications aimed at this server
  @impl true
  def join("server:" <> _id, _params, socket) do
    # Require user to be connected to UserChannel first
    case ChannelAuth.require_user_channel(socket) do
      :ok ->
        # TODO: Authorize that the user can access this server
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
