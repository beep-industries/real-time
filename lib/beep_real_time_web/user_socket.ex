defmodule BeepRealTimeWeb.UserSocket do
  use Phoenix.Socket

  # Channels mapping
  channel "text-channel:*", BeepRealTimeWeb.TextChannel
  channel "voice-channel:*", BeepRealTimeWeb.VoiceChannel
  channel "user:*", BeepRealTimeWeb.UserChannel
  channel "server:*", BeepRealTimeWeb.ServerChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # TODO: Authorize connections based on params (tokens) and connect_info
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
