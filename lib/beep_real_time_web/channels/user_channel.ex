defmodule BeepRealTimeWeb.UserChannel do
  use Phoenix.Channel
  alias BeepRealTime.Auth.KeycloakToken
  require Logger

  # Grace period in seconds before forcing disconnect after token expiry notification
  @disconnect_grace_period_ms 30000
  # Buffer time after actual expiry to check (ensures token is truly expired)
  @expiry_buffer_seconds 5

  # A user connects to this channel to get notifications targeted to this specific user
  @impl true
  def join("user:" <> user_id, _params, socket) do
    # Authorize that the connector is the same user
    if socket.assigns.user_id == user_id do
      # Track presence so other channels can verify user is connected
      {:ok, _ref} = BeepRealTimeWeb.Presence.track(socket, user_id, %{
        online_at: System.system_time(:second)
      })

      schedule_token_check_at_expiry(socket)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  # Handle token refresh from client
  @impl true
  def handle_in("refresh_token", %{"token" => token}, socket) do
    case KeycloakToken.verify_and_validate(token) do
      {:ok, claims} ->
        if claims["sub"] == socket.assigns.user_id do
          socket = assign(socket, :token_exp, claims["exp"])
          schedule_token_check_at_expiry(socket)
          {:reply, {:ok, %{status: "token_refreshed"}}, socket}
        else
          {:reply, {:error, %{reason: "user_mismatch"}}, socket}
        end

      {:error, reason} ->
        Logger.warning("Failed to refresh token: #{inspect(reason)}")
        {:reply, {:error, %{reason: "invalid_token"}}, socket}
    end
  end

  # Token expiry check scheduled at expiry time
  @impl true
  def handle_info(:check_token_expiry, socket) do
    now = System.system_time(:second)
    exp = socket.assigns[:token_exp] || 0

    if now >= exp do
      push(socket, "token_expired", %{message: "Your token has expired. Please provide a new token."})
      # Give client time to refresh, then disconnect if not refreshed
      Process.send_after(self(), :force_disconnect, @disconnect_grace_period_ms)
    else
      # Shouldn't happen, but reschedule if somehow triggered early
      schedule_token_check_at_expiry(socket)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:force_disconnect, socket) do
    now = System.system_time(:second)
    exp = socket.assigns[:token_exp] || 0

    if now >= exp do
      Logger.warning("Forcing disconnect for user #{socket.assigns.user_id} due to expired token")
      {:stop, {:shutdown, :token_expired}, socket}
    else
      # Token was refreshed in time, continue checking
      schedule_token_check_at_expiry(socket)
      {:noreply, socket}
    end
  end

  defp schedule_token_check_at_expiry(socket) do
    exp = socket.assigns[:token_exp] || 0
    now = System.system_time(:second)
    # Schedule check slightly after expiry to ensure token is truly expired
    delay_seconds = max(exp - now + @expiry_buffer_seconds, 0)
    delay_ms = delay_seconds * 1000

    Logger.debug("Scheduling token expiry check for user #{socket.assigns.user_id} in #{delay_seconds} seconds")
    Process.send_after(self(), :check_token_expiry, delay_ms)
    :ok
  end

  @impl true
  def terminate(_reason, socket) do
    Logger.debug("UserChannel terminated for reason: #{inspect(_reason)}")
    send(socket.transport_pid, :close)
    :ok
  end
end
