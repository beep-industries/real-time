defmodule BeepRealTimeWeb.HealthController do
  use BeepRealTimeWeb, :controller

  def show(conn, _params) do
    {redis_ok, redis_info} = redis_status()

    json(conn, %{
      status: "ok",
      socket_ok: true,
      queue_connected: false,
      components: [
        %{name: "endpoint", ok: true},
        %{name: "redis", ok: redis_ok, info: redis_info},
        %{name: "deduper", ok: Process.whereis(BeepRealTime.Signaling.Deduper) != nil}
      ]
    })
  end

  defp redis_status do
    case Process.whereis(BeepRealTime.Redis) do
      nil -> {false, %{reason: :not_started}}
      _pid ->
        case Redix.command(BeepRealTime.Redis, ["PING"]) do
          {:ok, "PONG"} -> {true, %{}}
          {:error, reason} -> {false, %{reason: inspect(reason)}}
        end
    end
  catch
    _class, _term -> {false, %{reason: :exception}}
  end
end
