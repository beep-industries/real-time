defmodule BeepRealTimeWeb.ServerChannel do
  use Phoenix.Channel

  # A user connects to this channel to receive notifications aimed at this server
  @impl true
  def join("server:" <> _id, _params, socket) do
    # TODO: Authorize that the user can access this server
    {:ok, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
