# Provider execution boundary v0.1

Status: executable bundle-independent subset. No native system action or external-app adapter is enabled merely by this profile.

## Admission

The v0.1 executable authority directly admits only an explicitly granted capability whose registered effect facts need no fresh user-presence approval under the conservative built-in policy: no private/credential data, no irreversible state change, no disruption, external service, credential use, destructive effect, or foreground-session requirement. Locked execution additionally requires the registered `allowedWhileLocked` fact. All other effects enter the exact one-shot flow in `operation-approval.md`; the legacy convenience method that explicitly forbids fresh approval still fails as `approvalRequired`.

Canonical parameter parsing, closed schema validation, active-granted device state, client identity, authorization epoch, grant revision, policy revision, and the exact capability grant are rechecked. The device/revision/grant checks occur again inside the SQLite transaction that inserts the durable operation and minimal event. A pre-transaction check is never sufficient.

## Execution claim

Before provider code is called, the authority:

1. loads the queued durable record and exact current capability descriptor;
2. matches provider ID, version, generation, execution revision, and schema version;
3. reparses and validates the supplied parameters, canonicalizes them, and recomputes the complete operation digest;
4. rejects a digest mismatch without changing or executing the legitimate queued record;
5. commits the exact execution claim in `operation-binding.md`.

Only a committed `.claimed` result permits provider invocation. A stale/expired claim returns its durable failed record and calls no provider. A grant change or suspension transaction may already have terminally fenced queued work; a later execution request returns that terminal record and does not retry it.

## Provider request and outcome

The provider receives only the operation UUID, registered capability ID, parsed schema-valid parameter value, and host deadline. Its runtime identity must exactly match the descriptor. It returns one of:

- `succeeded(resultJSON)`, where the host reparses, canonicalizes, and validates the result against the registered closed result schema before returning it;
- a closed host-known failure code: `provider.unavailable`, `provider.permissionDenied`, `provider.rejected`, `provider.timedOut`, or `provider.executionFailed`.

Malformed, oversized, unknown-field, or schema-invalid success data becomes `provider.invalidResult`. Arbitrary provider error text, paths, stack traces, credentials, or result bytes are never copied into the durable operation or security event. A successful v0.1 result is returned live but not durably retained; replay of a terminal operation returns its durable status, and the client uses Observe/resnapshot for current desired state. Durable privacy-reviewed result caching requires a later profile.

Provider calls are asynchronous and may expose best-effort cancellation. Native providers must have reviewed bounded implementations. External providers must be isolated behind authenticated bounded IPC whose adapter enforces deadline, cancellation, message size, and process-loss behavior; an in-process task cancellation is not treated as a guarantee that non-cooperative code stopped.

The host computes the remaining provider budget from the durable operation
expiry at execution claim and races invocation against a monotonic deadline.
The wall clock is not consulted again for that race. A host-side deadline
cancels the invocation task and returns without waiting for non-cooperative
provider code. Because task cancellation alone cannot prove that a side effect
did not occur, this path durably records `outcomeUnknown`, never
`provider.timedOut`, and the operation is never retried. A provider may return
`provider.timedOut` only when its reviewed adapter can prove that the effect was
not applied; otherwise it returns an unknown outcome. A production external
adapter must additionally terminate or invalidate its isolated execution
channel at the deadline. The bundle-independent race proves bounded host
response, not process termination.

A cancellation request for `queued` work commits `queued -> cancelled` without contacting a provider. A request for `running` work first commits `running -> cancelRequested`, then invokes the matching provider's best-effort cancellation hook; the boolean acknowledgement says only that the provider accepted the request. Repeating it returns the existing `cancelRequested` record and does not call the hook twice. The eventual provider outcome may legally produce `cancelled`, `succeeded`, `failed`, or, after recovery, `outcomeUnknown` according to the operation state machine.

If a provider effect completes but the terminal SQLite commit fails, success is not reported. The durable record remains in-flight and startup recovery changes it to `outcomeUnknown`; the effect is never silently retried.

## Startup reconciliation

Provider invocation parameters and live success results are intentionally not
durably retained in v0.1. Before any remote listener or local execution ingress
opens after process start, one atomic startup transaction therefore reconciles
every nonterminal durable operation:

- `running` and `cancelRequested` become `outcomeUnknown` with
  `operation.outcomeUnknown`, because an effect may have happened;
- `queued` becomes `failed` with `operation.hostRestarted`, because provider
  execution never began and the request cannot be reconstructed safely;
- terminal records remain unchanged.

No reconciled operation is invoked or retried. The transaction emits one
minimal host-owned event per transition and is idempotent. If it cannot commit,
startup remains fail closed and operation ingress stays unavailable.
