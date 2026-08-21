# Operation user-presence approval v0.1

Status: normative and executable for Act capabilities whose registered/host-raised effects require fresh approval.

## Signing construction

The client signs the following exact bytes with its separately stored P-256 approval key. `LP(x)` is `U32BE(byteCount(x)) || x`; UUIDs are 16 RFC 4122 network-order bytes; integers are unsigned big-endian.

```text
ASCII("MacCompanion/OperationApproval/v0.1")
LP(hostFingerprint[32])
LP(clientID[16])
LP(primaryConnectionID[16])
LP(approvalID[16])
LP(operationDigest[32])
LP(serverChallenge[32])
U64BE(issuedAtUnixMilliseconds)
U64BE(expiresAtUnixMilliseconds)
U16BE(selectedMajor)
U16BE(selectedMinor)
```

The signature is ECDSA P-256 over SHA-256 of these bytes and is transported as fixed-width `r || s`, 64 bytes. The wall-clock lifetime is positive and at most 60 seconds. The approval authority also has a host monotonic lifetime no longer than 60 seconds; the executable operation coordinator uses the shorter 30-second operation deadline.

`spec/fixtures/crypto/operation-approval-v0.1.json` contains authoritative signing bytes, an independently generated public key, and a valid raw signature. The throwaway private key was deleted after creating the public conformance vector.

## Issuance and display

The operation digest is the exact construction in `operation-binding.md`, so it transitively binds host/device/client identities, operation/capability/schema, provider identity and revisions, canonical parameter digest, effect facts, exact required host state, authorization/grant/policy revisions, operation expiry, and protocol version. The challenge separately binds the pinned host fingerprint and current authenticated primary connection.

Before signing, the official client displays host-owned localized capability title/summary, desired parameters in a schema-owned presentation, effect facts, host-raised restrictions, target Mac, and expiry. Provider text is presentation input only after bounds/sanitization and never changes the signed digest or policy.

## One-shot authority

The authority stores pending approval material only in boot/process memory. It revalidates the exact client, primary connection, authorization epoch, grant revision, policy revision, provider generation, execution revision, approval public key, monotonic deadline, and current grant before accepting a signature. A mismatch invalidates the authority. Expiry, invalid proof, successful proof, or explicit invalidation is terminal; a signature is never tried twice.

Repeating the same operation ID, canonical binding, and connection while approval remains pending returns the existing challenge. A different binding or connection conflicts and never replaces it. After a valid signature, the device/revisions/exact capability grant are checked again inside the same SQLite transaction that inserts the queued operation. If that transaction fails, no durable admission is reported and a new approval is required.
