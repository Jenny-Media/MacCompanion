# Agent local-status read service evidence — 2026-08-20

Status: bundle-independent construction under Xcode 27 beta. This is not an
XPC listener, audit-token/designated-requirement proof, signed process, or
release result.

`AgentLocalStatusReadServiceV1` is the narrow read capability for a future
already-authorized local IPC adapter. It accepts no caller role, audit token,
identifier, method name, request payload, or protocol version. This is
intentional: platform peer authentication and `LocalIPCAuthorizationPolicy`
must succeed before an XPC adapter calls the service, and bundle-independent
code cannot turn a caller-supplied role into proof.

Each read samples wall time exactly once and requests one coherent Agent status
version. Success receives the next actor-owned diagnostic sequence. Invalid or
unsafe time and any internal status failure map to the single closed
`sourceUnavailable` error, publish no partial payload, and consume no sequence.
Concurrent reads may share a wall-clock millisecond but cannot share a
sequence.

Four tests prove exact clock/status composition, sanitized invalid-clock
failure with sequence preservation, 32 unique concurrent reads, and the
separate policy admission of only authenticated menu-app/diagnostic-CLI callers
at v0.1 while same-role and version mismatch fail. The full public gate then
passed 54 indexed fixtures, all 687 Swift tests including 74 `CompanionAgent`
tests, macOS and iOS Simulator compile lanes, three no-network probe builds,
and diff hygiene.

Final acceptance still requires signed identities and an XPC adapter that
extracts the peer audit token, matches the exact designated requirement,
assigns the closed role locally, rejects wrong signers and stale versions, and
invalidates the read capability with the connection.
