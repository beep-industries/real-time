defmodule BeepRealTimeWeb.VoiceChannel do
  use Phoenix.Channel
  alias BeepRealTime.SFU.Client
  alias BeepRealTimeWeb.ChannelAuth
  alias BeepRealTimeWeb.Presence
  require Logger
  @max_endpoint_id 9_999_999_999_999
  @stunner_auth_url "http://stunner-auth.stunner-system:8088/ice?service=turn"

  # A user connects to be in the call; joining triggers call-connection mechanisms.
  @impl true
  def join("voice-channel:" <> uuid, params, socket) do
    # Require user to be connected to UserChannel first
    case ChannelAuth.require_user_channel(socket) do
      :ok ->
        user_id = socket.assigns[:user_id]

        if params["presence_only"] do
          # Presence-only mode: no SFU, just track presence
          socket = assign(socket, :presence_only, true)
          send(self(), :after_join)
          {:ok, socket}
        else
          disconnect_existing_voice_session(user_id)

          # Derive a shared u64 session_id from the channel key (UUIDv4)
          session_id = uuid_to_u64(uuid)
          Logger.info("User #{user_id} joining voice channel #{uuid} with session_id #{session_id}")

          # Assign a unique u64 endpoint_id for this socket within the current channel topic
          endpoint_id = generate_unique_endpoint_id(socket)

          socket =
            socket
            |> assign(:session_id, session_id)
            |> assign(:endpoint_id, endpoint_id)

        register_voice_session(user_id, self())

        # Fetch ICE/TURN configuration from STUNner auth service
        rtc_configuration = fetch_rtc_configuration()

        # Return the assigned ids and RTC configuration so the client can use them
        {:ok, %{session_id: session_id, endpoint_id: endpoint_id, user_id: user_id, rtc_configuration: rtc_configuration}, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns[:user_id]
    if socket.assigns[:presence_only] do
      {:ok, _} = BeepRealTimeWeb.Presence.track(socket, user_id, %{presence_only: true})
      push(socket, "presence_state", BeepRealTimeWeb.Presence.list(socket))
    end
    {:noreply, socket}
  end

  # Handle presence diffs from the server
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    broadcast(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    Logger.info("Terminating voice session for user #{socket.assigns.user_id}")
    user_id = socket.assigns[:user_id]
    if user_id do
      BeepRealTimeWeb.Presence.untrack(socket, user_id)
      if not socket.assigns[:presence_only] do
        unregister_voice_session(user_id, self())

        # Clean up SFU if needed
        if socket.assigns[:session_id] && socket.assigns[:endpoint_id] do
          Client.leave(socket.assigns.session_id, socket.assigns.endpoint_id)
        end
      end
    end

    :ok
  end

  # Handle forced disconnect from another join
  @impl true
  def handle_info(:force_disconnect, socket) do
    Logger.info("Forcing disconnect of voice session for user #{socket.assigns.user_id}")
    push(socket, "force_disconnect", %{reason: "joined_another_channel"})
    {:stop, :normal, socket}
  end

  defp register_voice_session(user_id, pid) do
    Logger.info("Registering voice session for user #{user_id}, and pid #{inspect(pid)}")
    Registry.register(BeepRealTime.VoiceSessionRegistry, {:voice, user_id}, pid)
  end

  defp unregister_voice_session(user_id, pid) do
    Logger.info("Unregistering voice session for user #{user_id} and pid #{inspect(pid)}")
    Registry.unregister_match(BeepRealTime.VoiceSessionRegistry, {:voice, user_id}, pid)
  end

  defp disconnect_existing_voice_session(user_id) do
    Logger.info("Disconnecting existing voice sessions for user #{user_id}")
    Registry.lookup(BeepRealTime.VoiceSessionRegistry, {:voice, user_id})
    |> Enum.each(fn {pid, _} ->
      Logger.info("Sending force_disconnect to existing voice session pid #{inspect(pid)} for user #{user_id}")
      if pid != self(), do: send(pid, :force_disconnect)
    end)
  end

  @impl true
  def handle_info(:gun_down, socket) do
    Logger.warning("SFU connection lost for user #{socket.assigns.user_id}")
    push(socket, "sfu_connection_lost", %{message: "Connection to SFU lost"})
    {:noreply, socket}
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

  # Deterministically map a UUIDv4 string to an unsigned integer with max 13 decimal digits.
  # This ensures all users joining the same voice-channel:{uuid} share the same session_id.
  # The result is always <= 9_999_999_999_999 (13 digits max).
  defp uuid_to_u64(uuid) when is_binary(uuid) do
    # Hash the UUID to get consistent bytes, then extract a 64-bit integer and bound it
    <<u64::unsigned-64, _::binary>> = :crypto.hash(:sha256, uuid)
    rem(u64, @max_endpoint_id + 1)
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

  defp fetch_rtc_configuration do
    request = Finch.build(:get, @stunner_auth_url)

    case Finch.request(request, BeepRealTime.Finch, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, rtc_config} ->
            rtc_config

          {:error, reason} ->
            Logger.warning("Failed to parse RTC configuration response: #{inspect(reason)}")
            %{}
        end

      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("RTC configuration request returned status #{status}")
        %{}

      {:error, reason} ->
        Logger.warning("Failed to fetch RTC configuration: #{inspect(reason)}")
        %{}
    end
  end
end
