defmodule BeepRealTimeWeb.UserSocket do
  use Phoenix.Socket
  alias BeepRealTime.Auth.KeycloakToken
  require Logger

  # Channels mapping
  channel "text-channel:*", BeepRealTimeWeb.TextChannel
  channel "voice-channel:*", BeepRealTimeWeb.VoiceChannel
  channel "user:*", BeepRealTimeWeb.UserChannel
  channel "server:*", BeepRealTimeWeb.ServerChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case KeycloakToken.verify_and_validate(token) do
      {:ok, claims} ->
        Logger.info("claims: #{inspect(claims)}, and sub: #{inspect(claims["sub"])}")
        socket =
          socket
          |> assign(:user_id, claims["sub"])

        {:ok, socket}

      {:error, _reason} ->
        Logger.warn("Failed to verify token, reason: #{inspect(_reason)}")
        :error
    end
  end

  @impl true
  def connect(_params, _socket, _connect_info) do
    # No token provided
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
