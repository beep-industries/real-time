defmodule BeepRealTime.Signaling.Deduper do
  @moduledoc """
  Redis-backed idempotency deduper.

  Uses Redis SET with NX + PX TTL to record seen event ids across the cluster.
  """
  use GenServer

  @default_ttl_ms :timer.minutes(10)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ttl = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    :telemetry.execute([:beep_real_time, :deduper, :init], %{ttl_ms: ttl}, %{backend: :redis})
    {:ok, %{ttl_ms: ttl}}
  end

  @doc """
  Returns true if id is new and stored. Returns false if already seen.

  Relies on Redis semantics: SET key value PX ttl NX -> "OK" when inserted, nil if exists.
  """
  def store_new?(id) when is_binary(id) do
    ttl = ttl_ms()
    key = redis_key(id)
    case Redix.command(BeepRealTime.Redis, ["SET", key, "1", "PX", Integer.to_string(ttl), "NX"]) do
      {:ok, "OK"} -> true
      {:ok, nil} -> false
      {:error, _} ->
        # Fail open: if Redis is down, we prefer to still broadcast (at-least-once),
        # so treat as new to avoid dropping notifications.
        true
    end
  end

  defp ttl_ms do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        %{ttl_ms: ttl} = :sys.get_state(pid)
        ttl
      _ -> @default_ttl_ms
    end
  end

  defp redis_key(id), do: "beep:rt:dedupe:" <> id
end
