# Local host-identity recovery composition evidence — 2026-08-21

## Result

The destructive host-identity recovery path now has a bundle-independent local
admission and presentation boundary. It is not a generic reset API and is not
reachable from remote protocol traffic or the diagnostic CLI.

`CompanionIPC` defines one immutable Agent-issued five-minute review, one exact
confirmation command, and one correlated completion receipt. The review binds
the current host UUID and fingerprint, a closed cause, and the sole scope
`invalidateAllPairingsGrantsAndWork`. The command can choose only its command
and recovery UUIDs; it cannot choose replacement identity, Keychain,
certificate, device, grant, route, or work facts. Unknown or missing fields,
unsafe times, zero/reused identifiers, broadened scope, unchanged replacement,
and mismatched receipts fail closed. The local role matrix permits review
publication only Agent-to-menu and recovery only menu-to-Agent.

`CompanionPresentation` exposes all five required consequences independently:
stop remote access, invalidate every paired phone, remove all capability grants,
fence queued and active work, and require re-pairing. Its reducer creates no
intent merely by displaying a review, retains the exact submitted command on
response loss, rejects mismatched receipts, discards unsubmitted authority on
Agent loss, and requires the same review before retry after reconnect.
`CompanionMacApp` adds one revision-fenced owner that generates distinct IDs,
keeps exact retry state, and rejects delayed success after Agent invalidation.
`CompanionMacUI` adds a compile-checked SwiftUI surface driven only by that
projection. It identifies the old or new public identity, renders all five
consequences as separate rows, permits cancel only before submission, exposes
only exact retry after failure, and offers no mutation while recovery or Agent
reauthorization is pending.

The security store schema is now v7. Recovery fencing atomically compares the
Agent-reviewed expected host UUID and fingerprint and retains the bounded exact
command/recovery/review identifiers, closed cause, and review/confirmation
times in the same transaction that revokes devices and fences the old host.
Completion atomically stores one last-recovery receipt while retaining that
intent. A replay is accepted only when every intent field matches; the recovery
UUID alone cannot replay or redirect the operation. The Security.framework
coordinator loads the already-completed listener identity without issuing or
deleting again.

After an Agent restart, the local recovery service reconstructs the exact
review and exact submitted command only from that durable intent. A distinct
Agent-to-menu `publishHostIdentityRecoveryResume` role method lets a restarted
menu app adopt the command without generating identifiers or asking for a
second confirmation. A changed command that reuses the recovery UUID is denied
both while fenced and after completion. The ordinary review-publication path
cannot imply that a command was already submitted.

The connection-scoped delivery actor accepts an already-authorized menu
surface, never a caller-supplied role or authorization flag. It serializes one
fresh review, durable resume, or resolution; acknowledges publication only
after the exact value is retained by the surface; and uses a generation fence
against reentrant publication, recovery, and endpoint invalidation. A failure
after the durable fence changes admission to exact-command retry, while a
pre-fence failure retains only the same review. Endpoint loss withdraws the
matching Mac presentation and clears in-memory review authority without
erasing durable recovery or interrupting store/Keychain convergence.
The production factory now requires that already-authorized surface and returns
only the connection-scoped delivery capability; it no longer exposes the raw
recovery service, concrete coordinator, or private required-audit store to the
future signed adapter.

## Verification

Focused package tests prove:

- strict payload round trips, expiry, unknown-field, scope, rotation, and exact
  receipt validation;
- complete destructive consequence order, failure retry, Agent-loss fencing,
  same-review restoration, and mismatch rejection;
- application-owner success, exact retry after response loss, delayed-response
  rejection, and identifier-reuse denial;
- atomic stale-host rejection, reviewed-intent rollback, schema-v6 migration
  without invented consent, persisted recovery receipt, and exact completed
  replay;
- no second key issuance, old-key deletion, recovery event, or executor call on
  post-commit retry;
- Agent review binding plus forged, expired, and invalidated review denial;
- exact fenced-command reconstruction after Agent restart and denial of a
  different command with the same recovery UUID; and
- menu-owner adoption after its own restart without new identifiers or a
  second destructive confirmation;
- fresh-review to failed-response to both-process restart convergence through
  the distinct durable resume delivery; and
- suspended publication invalidation, stale command rejection, and exact-only
  Mac surface withdrawal.

The complete unsigned repository gate validates 60 authoritative protocol
fixtures, dependency/privacy/SBOM/release policies, 954 Swift tests, iOS
Simulator and macOS cross-compiles, and three no-prompt/no-network probes.

## Remaining release gate

This evidence does not authenticate XPC or wire the already-authorized surface
to a signed connection, establish that the compile-checked
English copy is reviewed/localized, execute a real Secure Enclave/Keychain
recovery, or prove the workflow on a signed clean user. Final bundle identities,
designated-requirement/audit-token checks, stable Xcode, physical
first-unlock/key-loss testing, accessibility, and explicit user-observed
recovery remain required before release acceptance.
