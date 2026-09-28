# Local Interactive surface inventory reply

Status: normative for the v0.1 Agent-to-menu Interactive lease transport.

The authenticated local XPC `runtime.interactive.surface.targets` request
remains a nonempty canonical JSON payload of at most 4096 bytes. Its success
reply carries the complete menu-owned, privacy-filtered inventory snapshot of
at most 192 application and window candidates. It MUST NOT silently truncate
the snapshot by sort position. The canonical reply is bounded to 65536 bytes;
if it cannot fit, the command fails closed and no partial inventory is exposed.
The other Interactive lease command and success payloads retain the 4096-byte
bound. The reply preserves the session-scoped tokens and candidate order so
the Agent can return the same snapshot on the authenticated client channel.
The menu-owned inventory and the client-visible selection token expire after
at most 120000 monotonic milliseconds. Refresh replaces all tokens, and live
source and authorization checks still run at selection time.

The indexed `local-xpc-interactive-lease-transport-v0.1.json` fixture records
the exact transport bounds and failure rule. The client-visible candidate
schema and 192-candidate bound are specified in
`spec/interactive-control/v0/target-inventory-messages.md`.
