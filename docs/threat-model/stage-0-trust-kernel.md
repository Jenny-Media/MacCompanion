# Stage 0 Trust-Kernel Threat Model

Status: executable baseline draft. Every row must gain a fixture, deterministic test, or physical evidence reference before the dependent stage passes.

## Assets and authorities

- Host identity key and pinned fingerprint
- Client session and approval public-key bindings
- Pairing one-time secret and transcript
- Device grants, authorization epochs, policy revisions, approvals, and replay windows
- Durable operation identity and outcome
- Audit allowlist and minimal security events
- Interactive session, surface, coordinate, focus, and channel revisions

The Mac Agent is authoritative for network identity, grants, policy, epochs, durable work, and audit. The visible menu app is authoritative only for current capture/input execution under an agent lease. The client is authoritative only for its local user-presence signature and user intent.

## Threat cases

| Threat | Prevent or detect | Containment and recovery | Required evidence |
| --- | --- | --- | --- |
| Host-key substitution or hostile LAN service | QR-pinned host identity; pinned TLS; transcript binds host key and protocol | Abort without creating a device; rate-limit and audit safe code | Negative host-key and certificate fixtures |
| Pairing relay, race, or reused QR | 256-bit one-time secret; both-device transcript authentication string; atomic consumption; expiry | Invalidate the session after success, timeout, or bounded failures | Concurrent consume, wrong transcript, replay, and expiry tests |
| Malicious paired client | Explicit per-device grants; default deny; rate/size bounds; host revalidation | Suspend or revoke device; advance epoch; close transports and queued work | Stolen-client and over-grant tests |
| Replayed request or approval | Durable scoped replay windows; operation IDs; single-use challenges; session/protocol binding | Return existing operation only for identical digest; otherwise reject | Restart, reconnect, resumption, cross-host, and cross-session replay tests |
| Clock rollback or wall/monotonic disagreement | Host-issued expiries use a recorded monotonic deadline within one boot; wall time is diagnostic; restart invalidates boot-scoped challenges | Reject expired or ambiguous approval/replay state and require a fresh challenge | Wall rollback/forward, sleep, restart, and monotonic-boundary tests |
| Authorization race with queued work | Check epoch/grant/policy at receipt, durable admission, and execution claim | Stale queued work fails before provider execution | Deterministic epoch-change-at-claim test |
| Crash after external effect | Durable admission before execution; desired-state operations; explicit terminal persistence | Record `outcomeUnknown`; never silently retry | Crash hooks before/after effect and completion commit |
| Audit exhaustion or disk full | Separate security/audit quotas; bounded records; reserved emergency deny latch | Deny consequential writes; close remote service; recover locally before restart | Disk-full, corrupt-store, latch, restart, and repair tests |
| Forged or unauthorized local IPC | Audit-token and designated-requirement verification; role-specific interfaces; version negotiation | Reject peer, revoke lease, record bounded event | Same-user unsigned, wrong-team, wrong-role, stale-version tests |
| Menu app crash or disappearance | Agent owns leases and health; input transitions are ordered | Stop capture, release all input, suspend Control; preserve eligible Observe | Crash during click/key/drag/capture tests |
| Permission revocation | Recheck Screen Recording, Accessibility observation, and post-event permission separately | Stop affected path; publish exact unavailable reason; require local recovery | Individual grant/revoke/relaunch matrix |
| Lock or fast-user-switch ambiguity | Conservative host state; revisions fence pixels and input | Blank pre-lock frames, release input, destroy app/window/focus tokens, deny Control unless genuine lock UI is proved | Physical lock/switch/logout matrix |
| Surface or coordinate substitution | Ephemeral tokens plus surface/coordinate/focus revisions and client acknowledgement | Pause input and fall back visibly to the closest reliable pixel surface | Stale token/revision and modal fallback fixtures |
| Malicious provider metadata | Host-owned schemas, effect elevation, bounds, sanitization, final execution validation | Provider cannot gain exposure; disappear/change generation safely | Schema bomb, generation change, lowered-effect tests |
| Signed-update downgrade or mixed versions | Developer ID, notarization, Sparkle Ed25519, compatibility ranges, monotonic build versions | Refuse unsafe mixed control path; preserve recoverable admin UI | Old-to-new, interrupted, downgrade, signer-rotation tests |
| Lost or compromised host/client key | Device-specific revocation; host pins; no silent cloud key sync; explicit local recovery | Compromised client is revoked; lost client re-pairs as new identity; host-key recovery invalidates prior pins and requires local confirmation | Reinstall, restore, phone replacement, host migration, and suspected-compromise drills |
| Interface change exposes a public listener | Bind only selected private interfaces; continuously re-evaluate routes; identity never trusts route | Stop listener on disallowed transition without changing pairing | Wi-Fi/Ethernet/VPN/Tailscale/public transition tests |
| Prompt injection or autonomous expansion | Stage 7 model is an untrusted planner producing known requests only | Existing grants, approvals, epochs, and audit remain authoritative | Deferred until Stage 7 entry; no implicit control session |

## Security invariants

1. Pairing never grants Act or Control.
2. Network reachability never establishes Mac Companion identity.
3. A provider, client, route, or Remote Surface cannot expand its own grant.
4. No consequential work executes under a stale epoch, grant, policy, provider generation, or approval.
5. Screen or input bytes and app/window/focus content never enter durable audit or diagnostics.
6. Revocation and local suspend are safer than continuing: storage failure moves the service toward global remote denial, not retained access.
7. Unknown, ambiguous, malformed, oversized, or mixed-version state fails closed with a recoverable explanation.
