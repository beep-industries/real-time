defmodule BeepRealTimeWeb.VoiceChannel do
  use Phoenix.Channel

  # A user connects to be in the call; joining triggers call-connection mechanisms.
  @impl true
  def join("voice-channel:" <> _id, _params, socket) do
    # TODO: Authorize that the user can access this voice channel
    {:ok, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
