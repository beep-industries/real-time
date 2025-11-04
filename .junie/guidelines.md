Project Guidelines: Real-Time Signaling and Notifications

Purpose
- This document captures essential architectural context and conventions to guide future development of the real-time signaling and notifications stack in this project.

High-level Objective
- The objective of this project is to respond to the following design information as the Signaling Service, integrating with related services via queues:
  - Communities service: sends communities update events to queue.notification.communities
  - Messages service: sends messages update events to queue.notification.messages
  - Notifications service: consumes all the notifications from other services and publishes notifications to queue.notifications
  - Signaling service (this project): consumes messages from queue.notifications and queue.notification.chat (for quicker updates when a user is connected to a socket channel)

Queues and Flows
- queue.notification.communities
  - Producer: Communities service
  - Consumer: Notifications service
- queue.notification.messages
  - Producer: Messages service
  - Consumer: Notifications service
- queue.notifications
  - Producer: Notifications service
  - Consumer: Signaling service
- queue.notification.chat
  - Producer: (fast-path message updates; typically Messages/Notifications depending on design)
  - Consumer: Signaling service for immediate channel updates

Realtime Topics (Socket Channels)
- text-channel:id
  - A user connects to this channel to receive real-time updates about messages posted in the text channel identified by id.
- voice-channel:id
  - A user connects to this channel to be in the call; joining triggers call-connection mechanisms.
- user:id
  - A user connects to this channel to get notifications targeted to this specific user (friend-invite, message updates, etc.).
- server:id
  - A user connects to this channel to receive notifications aimed at this server (server-wide updates, etc.). Servers can have two states: active and non-active.

Notification Service Responsibilities
- Stores all notifications in a database (source of truth for notification history and unread counters).
- Consumes events from upstream services (communities, messages) via their respective queues.
- Aggregates/transforms events into notifications and publishes to queue.notifications for downstream (Signaling) distribution.

Notification Types (baseline)
- unread_channels
- unread_notifications
- friend_invite
- admin_message

Signaling Service Responsibilities (this project)
- Consume notifications from queue.notifications and queue.notification.chat.
- Fan-out relevant updates to connected WebSocket clients subscribed to the appropriate topics:
  - text-channel:id => message events, read/unread counters, edits/deletes
  - voice-channel:id => call state changes, participant join/leave, media/control signals
  - user:id => direct notifications (friend invites, DMs, mentions, admin messages)
  - server:id => server-wide updates (role changes, settings updates, announcements)
- Ensure low-latency delivery and graceful handling when clients disconnect/reconnect.

Delivery Semantics & Expectations
- Aim for at-least-once delivery from queues to Signaling; ensure idempotency in fan-out to avoid duplicate pushes.
- Deduplicate by notification id or event id when present.
- Preserve ordering per topic where feasible (e.g., per text-channel:id). Cross-topic global ordering is not guaranteed.

Failure Handling
- Use dead-letter queues (DLQ) for poison messages when decoding/validation fails.
- Log structured errors with enough context to reprocess.
- Consider backoff/retry for transient failures.

Security and Access
- Authorize topic subscriptions (e.g., user can only join channels/servers they have access to).
- Do not leak notification payloads across tenants or unauthorized users.
- Validate and sanitize all incoming event payloads from queues.

Performance Notes
- Prefer batched consumption/ack where supported by the queue client, but flush quickly for user-facing latency.
- For chat updates, use queue.notification.chat for the fast path to connected users; fall back to queue.notifications for general fan-out.
- Keep payloads compact; avoid sending large histories over realtime channels.

Schema and Event Shape (guidance)
- Common envelope fields recommended:
  - id (UUID), type, occurred_at (ISO8601), source (service), version
  - routing keys: topic_kind (text-channel|voice-channel|user|server), topic_id
- Notification-specific bodies should be versioned to allow evolution.

Testing Guidelines
- Add tests that simulate queue events and assert broadcast to the correct topics.
- Include cases for duplicates and out-of-order events to ensure idempotent handling and stable UI behavior.

Operational Notes
- Monitor consumer lag for queue.notifications and queue.notification.chat.
- Track socket connection counts per topic and broadcast rates.
- Expose health endpoints for queue connectivity and socket subsystem.

Conventions for this Repo
- Elixir/Phoenix code style per standard mix format.
- Keep domain boundaries clear: Notification Service owns persistence; Signaling Service owns transient delivery.
- Use telemetry events for critical operations: message consumed, message broadcast, error, retry.

Future Work (not exhaustive)
- Presence tracking on voice-channel:id and text-channel:id for richer UX.
- Per-user rate limiting and backpressure signaling.
- Encryption/obfuscation for sensitive notification payloads where required.

Last updated: 2025-10-27
