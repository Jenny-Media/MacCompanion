# Durable operation binding v0.1

Status: normative Stage 0 profile. Implementations MUST pass `spec/fixtures/crypto/operation-v0.1.json` before admitting an Act operation.

## Purpose

A durable `operationID` is bound to the exact request, authorization snapshot, provider implementation, required host state, expiry, and negotiated protocol version. Reusing an operation ID with the same digest returns the existing durable record. Reusing it with a different digest fails as `protocol.operationIDConflict`; it never replaces or executes the prior operation.

The store retains only the resulting digest and bounded routing/fencing metadata. It MUST NOT retain raw parameters, provider results, screen or input content, paths, credentials, or arbitrary error text in the operation record.

## Preconditions

- Parameters have passed their closed capability schema.
- Parameter JSON is canonical RFC 8785 JSON restricted to the safe-integer domain in `README.md`.
- `canonicalParametersSHA256 = SHA-256(canonical parameter UTF-8 bytes)`.
- `capabilityID`, `providerID`, and `providerVersion` are nonempty ASCII strings containing only `A-Z`, `a-z`, `0-9`, `.`, `_`, or `-`; their maximum UTF-8 lengths are 96, 96, and 64 bytes respectively.
- `schemaVersion`, every recorded revision, and `expiresAtUnixMilliseconds` are positive. Revisions and expiry are no greater than `9007199254740991`.
- UUID values use the 16 RFC 4122 network-order bytes.

## Construction

`operationDigestInput` is the following exact concatenation. `LP(x)` is `U32BE(byteCount(x)) || x`; integers are unsigned big-endian.

```text
ASCII("MacCompanion/Operation/v0.1")
LP(hostID)
LP(deviceID)
LP(clientID)
LP(operationID)
LP(UTF8(capabilityID))
U32BE(schemaVersion)
LP(UTF8(providerID))
LP(UTF8(providerVersion))
LP(providerGeneration)
LP(executionRevision)
LP(canonicalParametersSHA256)
effectSecurityEncoding
requiredHostStateCode
U64BE(authorizationEpoch)
U64BE(grantRevision)
U64BE(policyRevision)
U64BE(expiresAtUnixMilliseconds)
U16BE(selectedMajor)
U16BE(selectedMinor)
```

`operationDigest = SHA-256(operationDigestInput)`.

`effectSecurityEncoding` is exactly four bytes:

1. data access: `none=0`, `publicData=1`, `privateData=2`, `credentials=3`;
2. local-state change: `none=0`, `reversible=1`, `irreversible=2`;
3. flags: bit 0 may disrupt user, bit 1 invokes external service, bit 2 uses credentials, bit 3 destructive, bit 4 requires foreground session, bit 5 allowed while locked; bits 6–7 MUST be zero;
4. cancellation: `notApplicable=0`, `bestEffort=1`.

`requiresForegroundSession` and `allowedWhileLocked` cannot both be true.

`requiredHostStateCode` is one byte: `userSessionActive=1`, `userSessionLocked=2`, `otherConsoleUserActive=3`, `serviceStoppingForLogout=4`, `hostPreparingForSleep=5`. There is no wildcard state.

## Durable admission and execution claim

Admission atomically inserts a `pendingPolicy`, `awaitingApproval`, or `queued` record plus its bounded event. An implementation MAY move through policy/approval before the first durable insert, but it MUST durably insert `queued` before returning a durable operation reference. The per-device maximum is 10,000 retained records. Hitting it rejects a new operation; it never evicts a live or nonterminal record. Terminal records are retained for at least 30 days.

Immediately before provider code is called, one transaction MUST compare the current device state, authorization epoch, grant revision, policy revision, provider generation, execution revision, host state, and expiry with the bound record. A mismatch changes `queued` to `failed` with stable code `operation.authorizationRevoked`; expiry changes it to `failed` with `operation.expired`. A match changes `queued` to `running`. Provider code can start only after that commit succeeds.

On service recovery, every durable `running` or `cancelRequested` record atomically becomes `outcomeUnknown`; it is never retried. A `queued` record remains queued and must pass a fresh execution claim. Terminal records never restart. State transitions are exactly those in the protocol state machine.

## Conformance vector

`spec/fixtures/crypto/operation-v0.1.json` is authoritative for field order, length prefixes, enum bytes, input bytes, parameter hash, and final digest.
