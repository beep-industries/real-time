defmodule BeepRealTimeWeb.UserChannel do
  use Phoenix.Channel
  require Logger

  # A user connects to this channel to get notifications targeted to this specific user
  @impl true
  def join("user:" <> _id, _params, socket) do
    # TODO: Authorize that the connector is the same user or has permission
    {:ok, tref} = :timer.send_interval(10_000, :random_tick)
    {:ok, assign(socket, :random_timer_ref, tref)}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @impl true
  def handle_info(:random_tick, socket) do
    payload = %{
      id: :erlang.unique_integer([:positive, :monotonic]),
      type: "random_debug",
      occurred_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      body: %{
        message: random_message()
      }
    }

    push(socket, "random", payload)
    {:noreply, socket}
  end

  defp random_message do
    Logger.info("making random message")
    # simple random message generator
    n = :rand.uniform(1_000_000)
    adjectives = ["quick", "brave", "silent", "curious", "witty", "bright", "zesty"]
    nouns = ["fox", "coder", "sailor", "owl", "robot", "server", "packet"]
    adj = Enum.random(adjectives)
    noun = Enum.random(nouns)
    "#{adj}-#{noun}-#{n}"
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:random_timer_ref] do
      nil -> :ok
      tref -> :timer.cancel(tref)
    end

    :ok
  end
end
