defmodule BeepRealTimeWeb.VoiceChannel do
  use Phoenix.Channel
  alias BeepRealTime.SFU.Client
  require Logger
  @max_endpoint_id 9_999_999_999_999

  # A user connects to be in the call; joining triggers call-connection mechanisms.
  @impl true
  def join("voice-channel:" <> uuid, _params, socket) do

    user_id = socket.assigns[:user_id]
    # Derive a shared u64 session_id from the channel key (UUIDv4)
    session_id = uuid_to_u64(uuid)

    # Assign a unique u64 endpoint_id for this socket within the current channel topic
    endpoint_id = generate_unique_endpoint_id(socket)

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:endpoint_id, endpoint_id)

    # Return the assigned ids so the client can use them as needed
    {:ok, %{session_id: session_id, endpoint_id: endpoint_id, user_id: user_id}, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @impl true
  def handle_in("offer", %{"offer_sdp" => offer} = _payload, socket) do
    endpoint_id = socket.assigns.endpoint_id
    session_id = socket.assigns.session_id

    # Track presence for this endpoint (id) on first offer
    {:ok, _ref} =
      BeepRealTimeWeb.Presence.track(
        socket,
        socket.assigns.user_id,
        %{id: endpoint_id, user_id: socket.assigns.user_id, audio: false, video: false}
      )
    push(socket, "presence_state", BeepRealTimeWeb.Presence.list(socket))
    with true <- is_binary(offer) do
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
  def handle_in("leave", _payload, socket) do
    endpoint_id = socket.assigns.endpoint_id
    session_id = socket.assigns.session_id
    with true <- is_integer(session_id) do
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

  @impl true
  def handle_in("state_change", %{"audio" => audio, "video" => video}, socket) do
    {:ok, _ref} =
      BeepRealTimeWeb.Presence.update(
        socket,
        socket.assigns.user_id,
        %{id: socket.assigns.endpoint_id, user_id: socket.assigns.user_id, audio: audio, video: video}
      )
    push(socket, "presence_state", BeepRealTimeWeb.Presence.list(socket))
    {:noreply, socket}
  end

  defp parse_int(v) when is_integer(v), do: {v, ""}
  defp parse_int(v) when is_binary(v), do: Integer.parse(v)
  defp parse_int(_), do: :error

  # Deterministically map a UUIDv4 string to an unsigned 64-bit session id.
  # This ensures all users joining the same voice-channel:{uuid} share the same session_id.
  defp uuid_to_u64(uuid) when is_binary(uuid) do
    # Normalize and try to decode the raw 16 bytes of the UUID.
    hex = uuid |> String.downcase() |> String.replace("-", "")
    case Base.decode16(hex, case: :lower) do
      {:ok, <<_skip::binary-size(8), first8::binary-size(8)>>} ->
        :binary.decode_unsigned(first8)

      {:ok, <<first8::binary-size(8), _rest::binary-size(8)>>} ->
        :binary.decode_unsigned(first8)

      _ ->
        # Fallback: hash the uuid string to 64 bits
        <<u64::unsigned-64, _::binary>> = :crypto.hash(:sha256, uuid)
        u64
    end
  end

  # Generate a random u64 and ensure it does not collide with existing endpoint ids on this topic.
  defp generate_unique_endpoint_id(socket) do
    existing_ids =
      BeepRealTimeWeb.Presence.list(socket)
      |> Map.values()
      |> Enum.flat_map(fn %{metas: metas} -> metas end)
      |> Enum.map(fn meta -> meta[:id] end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    do_generate_unique_u64(existing_ids, 0)
  end

  defp do_generate_unique_u64(existing, tries) when tries >= 10 do
    # After several attempts, fall back to a monotonic base mapped into range
    # and then probe forward until we find a free id. This guarantees we still
    # return an id with <= 13 decimal digits while preserving per-topic uniqueness.
    base = :erlang.unique_integer([:positive, :monotonic]) |> rem(@max_endpoint_id + 1)
    find_free_id(existing, base)
  end

  defp do_generate_unique_u64(existing, tries) do
    # Produce a bounded random candidate so its decimal representation is <= 13 characters
    candidate = random_endpoint_id()
    if MapSet.member?(existing, candidate) do
      do_generate_unique_u64(existing, tries + 1)
    else
      candidate
    end
  end

  defp find_free_id(existing, candidate) do
    if MapSet.member?(existing, candidate) do
      next = if candidate >= @max_endpoint_id, do: 0, else: candidate + 1
      find_free_id(existing, next)
    else
      candidate
    end
  end

  defp random_endpoint_id do
    <<int::unsigned-64>> = :crypto.strong_rand_bytes(8)
    rem(int, @max_endpoint_id + 1)
  end
end
