# BeepRealTime (Signaling Service)

This service is the realtime signaling layer that broadcasts notifications to WebSocket clients subscribed to topics.

Getting started:

- Run `mix setup` to install and setup dependencies
- Start the endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
- Health endpoint: `GET /api/health`
- WebSocket endpoint: `ws://localhost:4000/socket/websocket`

Realtime topics (socket channels):
- `text-channel:id` — realtime updates about messages posted in the text channel
- `voice-channel:id` — call state changes and media/control signals
- `user:id` — direct notifications (friend invites, DMs, mentions, admin messages)
- `server:id` — server-wide updates (role changes, settings updates, announcements)

Event envelope (baseline):
- `id` (UUID), `type`, `occurred_at` (ISO8601), `source` (service), `version`
- routing: `topic_kind` ("text-channel"|"voice-channel"|"user"|"server"), `topic_id`
- `body` (map)

Dispatching events programmatically:

```elixir
BeepRealTime.Signaling.Dispatcher.consume(%{
  id: "00000000-0000-0000-0000-000000000001",
  type: "unread_notifications",
  occurred_at: DateTime.utc_now() |> DateTime.to_iso8601(),
  source: "notifications",
  version: 1,
  topic_kind: "user",
  topic_id: "123",
  body: %{unread: 5}
})
```

Delivery semantics:
- Fan-out is idempotent via Redis-based deduper on `id` (SET NX PX TTL).
- Ordering is best-effort per topic; cross-topic ordering not guaranteed.

Telemetry:
- `[:beep_real_time, :dispatch, :consume]`
- `[:beep_real_time, :dispatch, :broadcast]`
- `[:beep_real_time, :dispatch, :duplicate]`
- `[:beep_real_time, :deduper, :init]`

Configuration:
- Redis URL via env var REDIS_URL (default: redis://localhost:6379/0). The service starts a Redix connection named BeepRealTime.Redis used by the deduper.
- SFU gRPC address via env var SFU_GRPC_ADDR (default: 127.0.0.1:50051). The Voice channel sends Offer/Leave directly to the SFU Signaling gRPC service.

Security and access:
- Channel joins currently stub authorization; integrate token/user checks in `join/3` per channel and `UserSocket.connect/3`.

Health:
- `/api/health` returns JSON with component statuses, including Redis and the deduper. Queue consumers are not included in this repository.

Future work:
- Integrate with upstream queue(s) and add consumers when needed.
- Authorization and access control on topic joins.
- Presence and per-user rate limiting.
- Additional SFU operations as the gRPC API evolves.

## Voice Channel API (WebSocket)

Join topic: `voice-channel:{id}`

Push events:
- `offer` with payload: `{"session_id": <number|string>, "endpoint_id": <number|string>, "offer_sdp": <string>}`
  - Reply `ok`: `{"answer_sdp": <string>}`
  - Reply `error`: `{"error": <string>}`
- `leave` with payload: `{"session_id": <number|string>, "endpoint_id": <number|string>}`
  - Reply `ok`: `{}`
  - Reply `error`: `{"error": <string>}`

Implementation details:
- The service uses gRPC to call `signaling.Signaling/Offer` and `signaling.Signaling/Leave` at `SFU_GRPC_ADDR`.
- Responses and errors are proxied back to the socket caller. Telemetry spans are emitted under `[:beep_real_time, :voice, ...]`.

Troubleshooting (Voice/SFU):
- If your React client sees `{error: "sfu_unreachable"}` or a transport error when calling `channel.push("offer", ...)`, it means the SFU gRPC service is not reachable from this app.
  - Ensure the SFU is running and listening at `SFU_GRPC_ADDR` (default `127.0.0.1:50051`).
  - If the app runs inside Docker but your SFU runs on the host, consider using `SFU_GRPC_ADDR=host.docker.internal:50051` on Docker Desktop, or the Linux host-gateway option.
  - Socket replies return a compact error code (e.g., `sfu_unreachable`) to simplify client handling.


## Docker Compose (quick start)

This repository includes a docker-compose.yml for local testing with Redis.

How to run:
- docker compose up --build

After startup:
- Health: curl http://localhost:4000/api/health
- WebSocket endpoint: ws://localhost:4000/socket/websocket

Environment wired in compose:
- REDIS_URL=redis://redis:6379/0
- SFU_GRPC_ADDR=127.0.0.1:50051

Notes:
- The app binds to 0.0.0.0 in dev inside the container so you can access it from the host.
