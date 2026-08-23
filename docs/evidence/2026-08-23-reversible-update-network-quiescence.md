# Reversible update network quiescence

Date: 2026-08-23

Status: package and permanent-target composition pass on Xcode 27 beta. No app,
Agent, listener, local-XPC service, login role, TCC surface, network connection,
Sparkle download, or installer was started.

## Outcome

The Agent listener now owns a reversible update-admission lifecycle separate
from terminal shutdown. Close immediately rejects new work, cancels pending,
queued, classifying, and binding ingress, and retains already authenticated
primary, pairing, media, and input connections. Drain then closes every active
role. Reopen transitions a nonterminal closed or drained state and is a safe
no-op when already open; it restores advertisement-derived route and pairing
readiness, while terminal shutdown remains irreversible. Late classifier and
binder completions cannot cross a close or reopen generation.

The production Agent product exposes only those three exact effects. Its
presentation-capable local-XPC profile adds the closed, content-free
`update.network.close`, `update.network.drain`, and `update.network.reopen`
message families. Authorization is menu-app to Agent only, after the signed
peer handshake and menu-readiness acknowledgement. Client and server are
single-flight, deadline-bound, and generation-fenced; malformed, timed-out,
cancelled, stale, or replacement replies cannot complete a current command.
There is no payload and no generic local or remote capability authority.

The active dashboard product forwards those commands only during its retained
lifetime. `MacUpdateMenuRuntimeCompositionV0` binds them to the existing
candidate-owned runtime coordinator and Agent-stop saga. Its exact success
order is close, drain, Agent stop, then one already-prepared installer start.
Before-stop failures reconcile over a current known-live or replacement
authenticated generation. After-stop failures first recover the source Agent
and then invoke the same reconciliation seam, which must construct a
replacement authenticated generation before reopening.

The composition intentionally accepts no feed URL, archive, candidate builder,
release-evidence override, Sparkle controller, or arbitrary Agent authority.
The permanent application does not supply a prepared-installer adapter, so the
existing Sparkle hold point remains `.skip` and installation stays closed.

## Verification

Focused tests cover suspended classifier and binder close races, pending and
queued cancellation, all four active connection roles, route/advertisement
withholding and restoration, invalid lifecycle transitions, terminal fencing,
Agent-product forwarding, exact XPC dictionaries, method authorization,
profile construction, single-flight and generation fencing, timeout and
cancellation, dashboard-lifetime forwarding, exact install order, and both
recovery scopes. The complete repository gate is recorded in the checkpoint
commit: 73 authoritative fixtures, 35 update-policy fixtures, every
supply-chain, privacy, SBOM, signing, packaging, release-evidence, permanent-
target, and cross-platform validator, 1,590 MacCompanionKit tests, and 8
platform-probe tests pass on Xcode 27 beta.

## Deliberate non-claims

No real listener or XPC service executed and no active connection was drained.
No Agent was stopped or recovered, no receipt was written, and no prepared
installer was invoked. The live signed two-version update/failure matrix,
forced process loss during each transition, stable Xcode 26.6 repetition, and
final Sparkle adapter binding remain release gates.
