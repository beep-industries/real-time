defmodule BeepRealTimeWeb.HealthController do
  use BeepRealTimeWeb, :controller

  def show(conn, _params) do
    {redis_ok, redis_info} = redis_status()
    {queue_ok, queue_info} = queue_status()

    json(conn, %{
      status: "ok",
      socket_ok: true,
      queue_connected: queue_ok,
      components: [
        %{name: "endpoint", ok: true},
        %{name: "redis", ok: redis_ok, info: redis_info},
        %{name: "deduper", ok: Process.whereis(BeepRealTime.Signaling.Deduper) != nil},
        %{name: "queue", ok: queue_ok, info: queue_info}
      ]
    })
  end

  defp redis_status do
    case Process.whereis(BeepRealTime.Redis) do
      nil ->
        {false, %{reason: :not_started}}

      _pid ->
        case Redix.command(BeepRealTime.Redis, ["PING"]) do
          {:ok, "PONG"} -> {true, %{}}
          {:error, reason} -> {false, %{reason: inspect(reason)}}
        end
    end
  catch
    _class, _term -> {false, %{reason: :exception}}
  end

  defp queue_status do
    case BeepRealTime.Queue.Consumer.status("notification") do
      {true, info} -> {true, info}
      {false, info} -> {false, info || %{reason: :unknown}}
    end
  catch
    _class, _term -> {false, %{reason: :exception}}
  end
end
