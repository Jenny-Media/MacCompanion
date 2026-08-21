# Local Device Revocation Convergence Evidence

Date: 2026-08-21

Environment: bundle-independent local IPC, Agent, SQLite security store, deny
latch, and primary-session tests under Xcode 27 beta. This is unsigned
construction evidence. It is not authenticated XPC, live socket timing,
stable-toolchain, signed-candidate, or release evidence.

## Boundary completed

Local device revocation now starts from one closed five-minute Agent review
bound to a locally confirmed device name and exact durable state,
authorization epoch, and grant revision. Its command embeds the whole review;
its terminal receipt must correlate the command, review, device, successor
epoch, successor grant revision, and completion time. Strict decoding rejects
missing, extra, stale, nonterminal, unsafe-time, and mismatched shapes.

The Agent handler installs a security-administration ingress fence before any
storage or teardown await. That fence is independent of ordinary lifecycle
availability, closes the current primary transport and semantic session, and
cannot be reopened by a racing lifecycle-ready callback. Schema v8 then stores
the complete accepted command before latch activation. A second transaction
atomically compares the reviewed state/name, revokes authority, advances both
fences, removes grants, fences durable work, records one minimal event, and
stores the terminal receipt. Competing mutations touching the device fail
while the command is pending.

The latch stays active across the transaction, inventory refresh, and any
post-commit failure. Only after inventory converges does the Agent clear the
matching latch, publish nominal security posture, reopen ingress, and return
the receipt. Exact response-loss replay now reads SQLite and survives Agent
restart, including after the review window expires. Reuse of an ID with altered
content fails closed. Pending-row, completed-row-plus-latch, and legacy-latch
startup states reconcile before primary services are returned. The durable
binding expires only with the revoked-device tombstone.

## Verification

- Seven IPC tests cover name administration plus exact revocation
  review/command/receipt round trips, successor binding, half-open expiry,
  terminal state, and closed decoding.
- Eight revocation-coordinator tests cover ordinary and reviewed commit,
  migration-backed durable receipt replay, competing-mutation fencing, every
  transaction fault, tombstone cascade, legacy recovery, and stale review.
- Six Agent-handler tests cover complete order, same-process and cross-restart
  exact replay, stale review, injected database failure, post-commit restart
  convergence, and cleared-latch posture retry without a stranded primary
  fence or second revoke.
- Primary composition tests prove immediate session closure,
  lifecycle-independent denial, explicit security-owner release, and pending
  command completion before startup ingress is issued.

## Remaining gates

- Bind issuance/invalidation to final-identity audit-token and designated-
  requirement authenticated XPC; diagnostic CLI and remote clients must never
  obtain this authority.
- Prove route withdrawal, Observe disclosure stop, Interactive teardown, and
  socket closure under one second on signed physical Mac/iPhone sessions.
- Re-run on stable Xcode 26.6 and preserve signed-candidate evidence.
