# Client identity custody and publication v0.1

Status: normative bundle-independent custody and persistence boundary. The strict canonical local-record codec, bounded atomic file adapter, prepared-key restart reconciler, and compile-tested Security framework custody adapter are implemented. Live Keychain/Secure Enclave access-control behavior, iOS container/Data Protection and backup behavior, and physical-device evidence remain platform work.

## Separate nonexportable keys

One new pairing prepares two distinct P-256 signing keys and returns only their 65-byte X9.63 public keys plus opaque references:

- the `session` key uses `afterFirstUnlockThisDeviceOnly`, supports pairing proof and ordinary background reconnect after first unlock, and never requires a biometric prompt merely to reconnect;
- the `approval` key uses `whenUnlockedThisDeviceOnlyUserPresence` and requires fresh local user presence for each closed reason: pairing a Mac, approving an operation, starting legacy fresh-presence Interactive Control, or expanding a grant. Normal trusted-device remote desktop session starts use only the session key and do not access the approval key.

The references and public keys must be distinct. The custody interface has no private-key export, raw-private-key, socket, route, host-authority, or persistence method. Its signing methods receive only the normative signing input, an exact opaque reference, and—only for approval signing—one closed presence reason. The session-key adapter implements pairing and primary-authentication signing but cannot access the approval key.

The final iOS adapter must create this-device-only non-synchronizable keys using the release identity's Keychain access group and must prefer Secure Enclave custody where the supported-device matrix proves the required availability and access-control behavior. Unsupported, locked, missing, invalidated, restored, or migrated keys fail closed; they are never silently regenerated for an existing paired record.

`CompanionClientPlatform` now maps the session role to `AfterFirstUnlockThisDeviceOnly` without user presence and the approval role to `WhenUnlockedThisDeviceOnly` plus `privateKeyUsage` and `userPresence`. Secure Enclave creation is required by the production-default profile and may be disabled only by an explicit compatibility composition whose supported-device evidence justifies the software-key fallback. Creation publishes only the external public point, rolls back the session key if approval-key creation fails, and rolls back both keys if identity assembly fails. Signing looks up the private key by a role-specific opaque application tag, rechecks its public point, invokes message-mode ECDSA-P256-SHA256 exactly once, and converts Security's DER result to the protocol's fixed 64-byte raw form. Approval lookup uses `LAContext.localizedReason` selected from the closed presence reason; session signing has no presence prompt.

After restart, app composition loads each strict durable record and asks custody to register it. Registration preflights both Keychain objects and public points before exposing either opaque route. This construction has not been executed in the unsigned test suite because creation or approval signing would mutate Keychain state or present system UI. Final acceptance therefore still requires signed physical-device inspection of token ID, accessibility, access-control flags, non-synchronization, public-only export, prompt reason, and lock/reboot behavior.

## Atomic publication

Publication follows this order:

1. create both nonexportable keys and retain an unpublished prepared identity;
2. pass its public keys and session signer into the pairing authority;
3. accept only the pairing authority's exactly correlated monitor-only completion;
4. revalidate the complete prepared key pair in one custody-owner turn;
5. atomically commit one complete client record containing pairing/client/host/device IDs, host pin, bounded routes, initial authorization and revisions, both public keys, and both opaque key references; and
6. only after transaction success, publish the host to client presentation.

The durable store returns success for a pre-existing row only when the complete semantic record is identical. A conflicting pairing, host, device, pin, revision, or key reference fails. Storage failure returns the authority to retryable prepared state and exposes no partial host. Missing custody prevents the store call. User cancellation before the atomic store call discards the unpublished prepared identity and permanently closes that attempt. Once the store call begins, application composition defers cancellation until it returns because it cannot safely distinguish a commit that has not happened from one that completed while the response was pending.

Because Keychain and the client database are separate stores, atomicity here means keys are created first and the database is the sole visibility point. A crash before database commit can leave only unreachable orphan keys; a crash after commit leaves a complete record referring to already-created keys.

The local storage codec uses a closed schema-version-1 object, lowercase canonical UUIDs, bounded canonical endpoints, base64url public keys, exact key roles/protections, safe revisions, and the initial monitor-only state. It rejects unknown/missing fields, duplicate JSON keys, noncanonical bytes, broadened state, malformed keys, and private-key material by construction.

The bundle-independent atomic file adapter stores at most 64 complete records in an app-supplied private directory. Each canonical record is bounded to 64 KiB, written to a same-directory hidden temporary file, restricted to mode `0600`, synchronized, renamed as the sole visibility point, and followed by a directory synchronization; the owned directory is mode `0700`. Restart accepts only canonical `<pairing-id>-<client-id>.json` regular files whose decoded identity matches the filename. Visible unknown files, symlinks, noncanonical bytes, oversized records, quota overflow, reused pairing/host/device identities, or reused cross-role key references fail closed. Hidden pending files are never records. Faults before rename publish nothing; a reported fault after rename is resolved by an exact idempotent retry.

This adapter is not itself the final iOS storage claim. The app composition must place its directory in the correct application container, select and inspect the required Data Protection class and backup exclusion, prevent multi-process writers, and prove lock, crash, restore, reinstall, and storage-pressure behavior on physical devices.

At restart, the reconciler preflights the complete prepared-key inventory before mutation. A prepared identity with an exact committed record and usable keys is idempotently adopted; one with no record is idempotently deleted as an orphan. A record with conflicting references/public keys or a missing committed key fails closed before any adoption or deletion, preserving recovery evidence. A committed record whose key later disappears is unusable and requires explicit re-pairing; it never triggers silent identity replacement.

## Acceptance boundary

Bundle-independent tests cover exact role/protection separation, distinct public keys/references, opaque-reference signing, closed approval-presence reasons, monitor-only record validation, key-presence failure, injected publication rollback and retry, completion mismatch, cancellation, canonical storage round trip, unknown/noncanonical/broadened record rejection, bounded multi-host atomic-file persistence, permissions, conflict/quota rejection, pre/post-rename fault convergence, real-store restart adoption, orphan cleanup, no-mutation conflict preflight, exact Security construction profiles/configuration bounds, and DER-to-raw P-256 conversion. Release acceptance still requires Security framework access-control inspection, app-container protection/backup inspection, device-lock/first-unlock/biometric/passcode/restore/reinstall tests, crash-loop reconciliation against the actual Keychain and container, and physical signing through both keys.

## Trusted-device remote desktop composition

The normal MVP selects the `trustedDevice` session consent profile from
`spec/interactive-control/v0/security-profile.md`. A fresh, exactly bound
interactive challenge is signed with the existing nonexportable session key.
Key protection and stored public keys remain unchanged; existing Control-enabled
pairings need no re-pairing. The presence-bound approval key is retained for
deferred operation/grant compatibility and cannot sign a trusted session start.
