defmodule BeepRealTime.Signaling.Dispatcher do
  @moduledoc """
  Maps notification events to socket topics and broadcasts to connected clients.

  Expects an event envelope with fields:
  - id (UUID)
  - type
  - occurred_at (ISO8601)
  - source
  - version
  - topic_kind ("text-channel" | "voice-channel" | "user" | "server")
  - topic_id (string)
  - body (map)

  Emits telemetry events:
  - [:beep_real_time, :dispatch, :consume]
  - [:beep_real_time, :dispatch, :duplicate]
  - [:beep_real_time, :dispatch, :broadcast]
  - [:beep_real_time, :dispatch, :error]
  """

  alias BeepRealTime.Signaling.Deduper
  alias BeepRealTimeWeb.Endpoint

  @spec consume(map()) :: :ok | {:error, term()}
  def consume(event) when is_map(event) do
    meta = %{source: Map.get(event, "source"), type: Map.get(event, "type")}
    :telemetry.execute([:beep_real_time, :dispatch, :consume], %{count: 1}, meta)

    with :ok <- validate(event) do
      id = get_in(event, ["id"]) || get_in(event, [:id])
      if id && Deduper.store_new?(to_string(id)) do
        topic = build_topic(event)
        payload = build_payload(event)
        Endpoint.broadcast(topic, "notification", payload)
        :telemetry.execute([:beep_real_time, :dispatch, :broadcast], %{count: 1}, Map.put(meta, :topic, topic))
        :ok
      else
        :telemetry.execute([:beep_real_time, :dispatch, :duplicate], %{count: 1}, meta)
        :ok
      end
    else
      {:error, reason} ->
        :telemetry.execute([:beep_real_time, :dispatch, :error], %{count: 1}, Map.put(meta, :reason, reason))
        {:error, reason}
    end
  end

  defp validate(%{"topic_kind" => kind, "topic_id" => id}) when is_binary(kind) and is_binary(id), do: :ok
  defp validate(%{topic_kind: kind, topic_id: id}) when is_binary(kind) and is_binary(id), do: :ok
  defp validate(_), do: {:error, :invalid_envelope}

  defp build_topic(%{"topic_kind" => kind, "topic_id" => id}), do: topic(kind, id)
  defp build_topic(%{topic_kind: kind, topic_id: id}), do: topic(kind, id)

  defp topic(kind, id) when kind in ["text-channel", "voice-channel", "user", "server"], do: kind <> ":" <> id
  defp topic(kind, id), do: kind <> ":" <> to_string(id)

  # Keep payload compact; forward both envelope and body for clients to decide
  defp build_payload(%{} = ev) do
    %{
      id: Map.get(ev, "id") || Map.get(ev, :id),
      type: Map.get(ev, "type") || Map.get(ev, :type),
      occurred_at: Map.get(ev, "occurred_at") || Map.get(ev, :occurred_at),
      source: Map.get(ev, "source") || Map.get(ev, :source),
      version: Map.get(ev, "version") || Map.get(ev, :version),
      body: Map.get(ev, "body") || Map.get(ev, :body)
    }
  end
end
