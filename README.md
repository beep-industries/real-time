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

Join topic: `voice-channel:{uuid}`

Join response (payload from server):
- `{ "session_id": <uint64>, "endpoint_id": <uint64> }`
  - `session_id` is a shared unsigned 64-bit identifier derived deterministically from the topic UUID. All users joining the same `voice-channel:{uuid}` share this `session_id`.
  - `endpoint_id` is a per-socket unsigned 64-bit identifier unique within the topic.

Push events:
- `offer` with payload: `{"offer_sdp": <string>}`
  - Reply `ok`: `{"answer_sdp": <string>}`
  - Reply `error`: `{"error": <string>}`
- `leave` with payload: `{}`
  - Reply `ok`: `{}`
  - Reply `error`: `{"error": <string>}`

Implementation details:
- The server derives `session_id` from the topic UUID by mapping it to a stable 64-bit unsigned integer. This ensures at-least-once/idempotent compatibility with downstream SFU systems expecting a numeric session id.
- The service uses gRPC to call `signaling.Signaling/Offer` and `signaling.Signaling/Leave` at `SFU_GRPC_ADDR`, passing the derived `session_id` and the per-socket `endpoint_id`.
- Responses and errors are proxied back to the socket caller. Telemetry spans are emitted under `[:beep_real_time, :voice, ...]`.

Troubleshooting (Voice/SFU):
- If your React client sees `{error: "sfu_unreachable"}` or a transport error when calling `channel.push("offer", ...)`, it means the SFU gRPC service is not reachable from this app.
  - Ensure the SFU is running and listening at `SFU_GRPC_ADDR` (default `127.0.0.1:50051`).
  - If the app runs inside Docker but your SFU runs on the host, consider using `SFU_GRPC_ADDR=host.docker.internal:50051` on Docker Desktop, or the Linux host-gateway option.
  - Socket replies return a compact error code (e.g., `sfu_unreachable`) to simplify client handling.


  ### Collision analysis: UUIDv4 -> uint64 session_id

  How we derive the numeric `session_id` today:
  - We take the raw 16 bytes of the UUIDv4 and decode them.
  - We use the last 8 bytes (bytes 9–16) and interpret them as an unsigned 64-bit integer.
  - If the UUID cannot be parsed, we fall back to `sha256(uuid)` and take the first 8 bytes (64 bits).

  Effective entropy:
  - A UUIDv4 has 122 random bits (6 bits are reserved for version/variant).
  - The last 8 bytes include the variant field, which fixes 2 of those 64 bits.
  - Therefore, the derived `session_id` has ~62 bits of entropy when the input is a valid UUIDv4.
  - In the fallback hashing path we have a full 64 bits of entropy (truncated SHA-256).

  Collision probability (birthday bound approximation):
  - For M distinct voice-channel UUIDs mapped to 62 random bits, the chance of at least one collision is approximately:
    p ≈ 1 - exp(-M·(M-1) / (2 · 2^62)) ≈ M^2 / (2 · 2^62) for small p.
  - Numeric intuition for 62-bit space (2^62 ≈ 4.61e18):
    - M = 1,000 channels → p ≈ 1.1e-13 (negligible)
    - M = 1,000,000 channels → p ≈ 1.1e-7 (0.000011%)
    - M = 10,000,000 channels → p ≈ 1.1e-5 (0.0011%)
    - M = 100,000,000 channels → p ≈ 1.1e-3 (0.11%)
    - M = 1,000,000,000 channels → p ≈ 1.08e-1 (~10.8%)

  Interpretation:
  - If your total population of distinct voice channels is ≲ 10 million, the collision risk is around 1 in 100,000 or better, which is generally acceptable for non-adversarial IDs.
  - At very large scales (hundreds of millions to billions of distinct channels), birthday collisions become non-negligible.

  If you need to further reduce collision risk:
  - Switch to hashing for all inputs: derive `session_id = first_8_bytes(sha256(uuid))` to get a uniform 64-bit spread (still uses 64-bit space, but avoids the 2 fixed variant bits and any structural bias). This improves distribution but does not change the fundamental birthday bound of 64-bit spaces.
  - Or move to a wider numeric domain if your SFU supports it (e.g., 96/128-bit IDs). With 128 bits, collisions are effectively impossible in practice.

  Operational mitigations:
  - Log and alarm on SFU errors indicating duplicate/conflicting sessions, including `uuid`, `session_id`, and `endpoint_id` for investigation.
  - Because `session_id` is deterministic from the topic UUID, any collision would mean two different UUIDs mapped to the same 64-bit number; you can hot-patch by switching to the hashing variant if that ever occurs.


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
