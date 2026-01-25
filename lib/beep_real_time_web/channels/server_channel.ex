defmodule BeepRealTimeWeb.ServerChannel do
  use Phoenix.Channel
  alias BeepRealTimeWeb.ChannelAuth
  alias BeepRealTimeWeb.Presence

  # A user connects to this channel to receive notifications aimed at this server
  @impl true
  def join("server:" <> _id, _params, socket) do
    # Require user to be connected to UserChannel first
    case ChannelAuth.require_user_channel(socket) do
      :ok ->
        # TODO: Authorize that the user can access this server
        send(self(), :after_join)
        {:ok, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns[:user_id]
    {:ok, _} = Presence.track(socket, user_id, %{online_at: inspect(System.system_time(:second)), user_id: user_id})
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    broadcast(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    user_id = socket.assigns[:user_id]
    Presence.untrack(socket, user_id)
    :ok
  end
end
