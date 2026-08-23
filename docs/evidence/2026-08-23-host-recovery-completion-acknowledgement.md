# Host-recovery completion acknowledgement

Date: 2026-08-23

## Gap closed

Host-identity recovery already retained its intent and exact completion receipt
so a lost reply could not repeat the destructive operation. That journal also
kept every later Agent launch in the recovery-only product, however, because
there was no proof that the authenticated menu had decoded and retained the
receipt before the Agent returned to ordinary enabled or disabled startup.

The local protocol now completes recovery with a second, distinct command. The
menu first validates the exact `LocalHostIdentityRecoveredReceiptV0`, then sends
that complete value in
`command.host-identity.recovery-complete.acknowledge`. Success echoes only the
same receipt; handled failure is content-free. This is not a retry of recovery
and carries no pairing, grant, provider, Interactive, listener, or general
Agent authority.

## Durable boundary

The Agent accepts acknowledgement only from the authenticated recovery profile
and only after that connection-scoped delivery returned the identical receipt.
The persistence transaction independently requires all of these facts to match:

- the acknowledgement correlation is the durable recovery command ID;
- the durable intent names the same recovery, replaced host, and old
  fingerprint;
- the durable completion receipt is byte-for-value identical;
- the current host identity is ready, has no recovery fence, and names the
  receipt's new host, new fingerprint, and completion time.

Only then does one SQLite transaction remove the intent and receipt and append
the coarse `hostIdentity.recoveryAcknowledged` security event. Any audit-write
failure rolls the deletion back. The new identity and existing recovery audit
history remain. No old device, grant, route, operation, or session is restored.

Before that transaction, startup sees the completed journal and selects the
same recovery-only product even though the new key is usable; it can republish
the retained command and replay the exact receipt. After the transaction, a
crash is safe without another flag: the next launch sees no recovery journal
and follows canonical enabled or disabled intent.

## Reply and restart convergence

After the durable transaction, the Agent's stable recovery command authority
records the exact acknowledged receipt. The XPC server asks the application
owner for one launchd restart after the acknowledgement reply send succeeds,
or after a transport failure makes that now-durable reply impossible. Endpoint
invalidation is a second path to the same one-shot latch, so replacement and
teardown cannot lose the restart request or request it twice. The restart
closure is installed before the recovery product starts.

A forged, stale, premature, cross-generation, mismatched, or duplicate-after-
retirement acknowledgement cannot clear the journal or request restart. If the
first recovery reply was lost, ordinary durable replay remains the only
semantic retry. If the acknowledgement reply is lost after commit, the menu
may observe transport failure, but recovery is not repeated and the next Agent
launch converges from durable truth.

## Verification

Focused tests cover exact acknowledgement and duplicate rejection, wrong-
command refusal, rollback when audit insertion fails, completed-journal startup
replay, ordinary startup after retirement, service and delivery convergence,
closed local-IPC role authorization, sequential transport gating, exact C
message parsing, and restart-latch installation before product start.

The complete repository gate passes over 1,196 repository files, 2,191
historical blob-paths, 73 indexed JSON fixtures, 372 Swift source files, 1,611
MacCompanionKit Swift tests, eight platform-probe tests, every supported
cross-build, and the three no-prompt/no-network probes.

## Deliberately still open

No signed service was launched and no real Keychain key, host identity, device,
grant, route, work item, or audit database was changed by this checkpoint.
Signed reciprocal two-process execution, real Secure Enclave/Keychain
replacement, launchd restart observation, first-unlock and response-loss fault
injection, stable Xcode, and explicit user-observed destructive confirmation
remain release-evidence gates.
