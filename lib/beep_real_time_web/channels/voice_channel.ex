defmodule BeepRealTimeWeb.VoiceChannel do
  use Phoenix.Channel
  alias BeepRealTime.SFU.Client

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

  @impl true
  def handle_in("offer", %{"session_id" => s, "endpoint_id" => e, "offer_sdp" => offer} = _payload, socket) do
    with {session_id, ""} <- parse_int(s),
         {endpoint_id, ""} <- parse_int(e),
         true <- is_binary(offer) do
      :telemetry.execute([:beep_real_time, :voice, :offer, :request], %{count: 1}, %{session_id: session_id, endpoint_id: endpoint_id})
      case Client.offer(session_id, endpoint_id, offer) do
        {:ok, answer_sdp} ->
          :telemetry.execute([:beep_real_time, :voice, :offer, :ok], %{count: 1}, %{session_id: session_id, endpoint_id: endpoint_id})
          {:reply, {:ok, %{answer_sdp: answer_sdp}}, socket}

        {:error, reason} ->
          :telemetry.execute([:beep_real_time, :voice, :offer, :error], %{count: 1}, %{session_id: session_id, endpoint_id: endpoint_id, reason: reason})
          {:reply, {:error, %{error: reason}}, socket}
      end
    else
      _ -> {:reply, {:error, %{error: "invalid_payload"}}, socket}
    end
  end

  @impl true
  def handle_in("leave", %{"session_id" => s, "endpoint_id" => e}, socket) do
    with {session_id, ""} <- parse_int(s),
         {endpoint_id, ""} <- parse_int(e) do
      :telemetry.execute([:beep_real_time, :voice, :leave, :request], %{count: 1}, %{session_id: session_id, endpoint_id: endpoint_id})
      case Client.leave(session_id, endpoint_id) do
        :ok ->
          :telemetry.execute([:beep_real_time, :voice, :leave, :ok], %{count: 1}, %{session_id: session_id, endpoint_id: endpoint_id})
          {:reply, {:ok, %{}}, socket}

        {:error, reason} ->
          :telemetry.execute([:beep_real_time, :voice, :leave, :error], %{count: 1}, %{session_id: session_id, endpoint_id: endpoint_id, reason: reason})
          {:reply, {:error, %{error: reason}}, socket}
      end
    else
      _ -> {:reply, {:error, %{error: "invalid_payload"}}, socket}
    end
  end

  defp parse_int(v) when is_integer(v), do: {v, ""}
  defp parse_int(v) when is_binary(v), do: Integer.parse(v)
  defp parse_int(_), do: :error
end
