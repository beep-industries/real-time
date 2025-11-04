defmodule BeepRealTimeWeb.TextChannel do
  use Phoenix.Channel

  # A user connects to this channel to receive real-time updates about messages posted in the text channel identified by id.
  @impl true
  def join("text-channel:" <> _id, _params, socket) do
    # TODO: Authorize that the user can access this text channel
    {:ok, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
