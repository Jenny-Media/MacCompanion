# Mac Companion Persistence Profile v0

Status: Stage 0 executable storage profile. This file is normative for the first service-owned security database. It does not implement Keychain access control, boot-scoped pairing-secret/session memory, provider results, or general audit detail; those require their own fixture-backed additions before use. It does define durable host-identity metadata/recovery fencing, durable operation identity and execution-claim fencing, the one-time pairing-consumption record, and the emergency latch byte format.

## 1. Authorities and files

The per-user Agent owns all durable security state. The visible menu app, iOS client, providers, and diagnostic CLI never open these files.

Two independent durable mechanisms are required:

1. `security.sqlite3` stores public host-identity metadata, recovery fences, device identities, public keys, authorization state, epochs, grant revisions, request-binding digests, bounded operation metadata, and minimal security events transactionally.
2. A fixed-size emergency deny-latch file is preallocated during local enablement and updated without SQLite page allocation. It records global remote denial plus any device whose intended revocation is not yet durable.

The SQLite database is not the emergency latch. A successful SQLite migration or transaction does not prove the latch works. Until torn-write recovery, preallocation, `fsync`, disk-full, restart, and repair tests pass, production remote startup and device revocation remain incomplete.

### Emergency latch v1 format

The latch file is exactly 4,096 bytes and mode `0600`. It contains two 2,048-byte slots. All multibyte integers are unsigned big-endian. Each slot is:

| Offset | Length | Value |
| --- | ---: | --- |
| 0 | 8 | ASCII `MCDENY01` |
| 8 | 2 | format version, exactly 1 |
| 10 | 1 | state: 0 clear, 1 active |
| 11 | 1 | zero |
| 12 | 8 | monotonically increasing generation |
| 20 | 16 | RFC 4122 device UUID bytes, or all zero |
| 36 | 8 | non-negative safe-integer wall time in milliseconds |
| 44 | 4 | reason: 0 clear, 1 revocation in progress, 2 security store unavailable, 3 integrity failure |
| 48 | 32 | SHA-256 of ASCII `MacCompanion/EmergencyDenyLatch/v1` followed by bytes 0–47 |
| 80 | 1,968 | zero |

Both slots begin as identical valid clear generation 0 records. An update overwrites the lower-generation slot with generation `max + 1`, then calls `fsync`. A read requires both slots to be structurally and cryptographically valid; any invalid slot, equal-generation disagreement, unsafe timestamp, impossible state/reason/device combination, or generation exhaustion yields corrupt/deny. Otherwise the higher generation is authoritative.

Revocation uses a pre-armed sequence: write and `fsync` an active `revocation in progress` latch, attempt the SQLite epoch/grant/event transaction, close remote work on any failure, and clear/`fsync` the latch only after the durable transaction succeeds. A crash at any point is therefore clear-before-intent, deny-with-pending-intent, or deny-after-commit; it is never a silently active revoked identity. If activating the latch itself cannot be durably verified, revocation does not proceed and the running service enters global in-memory denial with a local recovery requirement.

Host private keys remain in the per-user Keychain. The database may store public fingerprints and identifiers but never private-key bytes, pairing QR secrets, approval secrets, screen/input content, app/window/focus content, filesystem paths, or arbitrary provider text.

## 2. SQLite opening profile

- Open read-write/create with full mutex protection; a higher actor or serialized executor still owns access.
- Set `foreign_keys=ON`, `trusted_schema=OFF`, `journal_mode=WAL`, `synchronous=FULL`, and a bounded busy timeout.
- Migrations use `BEGIN EXCLUSIVE` and update `PRAGMA user_version` only in the same successful transaction.
- Ordinary security writes use `BEGIN IMMEDIATE`; no transaction may suspend or invoke provider, network, UI, or Keychain code.
- A schema newer than the executable understands is refused. A corrupt database is never silently replaced or treated as an empty trusted store.
- Database and sidecar permissions, backup exclusion, file protection, clean uninstall, and rollback compatibility are release-target acceptance tests and cannot be proved by a Swift package test.

## 3. Schema version 7

`host_identity_bootstrap` is an optional singleton containing one candidate host
UUID, one exact bounded Keychain application tag, and a non-negative start time.
It is written before Keychain mutation. Repeating bootstrap adopts the existing
row rather than replacing it. Completion requires an exact host UUID and tag
match, inserts the ready `host_identity`, deletes the bootstrap row, and inserts
`hostIdentity.established` in one transaction. It contains no key bytes,
certificate, fingerprint, route, or remote-controlled value.

`host_identity` is an optional singleton. Its ready form contains the random host UUID, bounded Keychain application tag, 32-byte SPKI fingerprint, bounded public certificate DER and validity, establishment/update times, and no recovery ID. Its `fencedForReplacement` form retains those old public values plus one recovery UUID while every old device remains revoked. It never contains private-key bytes or an exportable key reference.

`host_identity_recovery_receipt` is an optional singleton retained after the
latest completed replacement. It contains only the recovery UUID, replaced host
UUID/fingerprint, new host UUID/fingerprint, and non-negative completion time.
Both UUID and fingerprint pairs must differ. It contains no command text,
private-key material, Keychain tag, certificate, route, device, grant, or work
content. It is replaced only by a later successfully completed recovery.

`host_identity_recovery_intent` is an optional singleton written only with the
recovery fence and retained through completion. It contains the command,
recovery, and review UUIDs; reviewed old host UUID and 32-byte fingerprint; one
of the three closed recovery causes; exact five-minute review creation and
expiry times; and the confirmation time inside that window. It contains no
serialized IPC payload, UI copy, scope parameter, private-key material,
Keychain tag, certificate, route, device, grant, or work content. The row is
the sole durable authority for reconstructing a fenced review and for deciding
whether a command or completed-response retry is exact.

Migration from schema v1 adds the empty host-identity table without inventing a host identity. Migration from v2 adds an empty durable-operation table without inventing work. Migration from v3 adds the empty local device-display-name table without inventing or trusting a remote name. Migration from v4 adds the empty bootstrap singleton without inventing an identity or key reference. Migration from v5 adds an empty last-recovery receipt without inventing a recovery. Migration from v6 adds an empty reviewed-intent singleton without inventing local authorization; a legacy fenced row without an intent remains denied and requires explicit local repair rather than reconstructed consent. Fresh creation installs the complete schema as v7. Bootstrap completion consumes the exact pending row while inserting the ready identity and its minimal event in one transaction; a second establishment is rejected.

`device_authorizations` contains one row per durable paired identity:

- canonical device and client UUIDs;
- 65-byte session and approval P-256 public keys;
- state limited to `activeMonitorOnly`, `activeGranted`, `suspended`, or `revoked`;
- authorization epoch and grant revision in `1...9_007_199_254_740_991`;
- the policy revision bound to the pairing commit in the same range;
- non-negative creation/update wall times and nullable revocation wall time.

`device_grants` contains closed registered capability IDs keyed by device. Pairing creates no Act or Control grant. Grant replacement, state transition, authorization-epoch advance, grant-revision advance, and the minimal security event are one transaction.

`device_display_names` contains at most one locally confirmed presentation name per retained device. Its UTF-8 value is 1–64 bytes and is accepted only through the typed `DeviceDisplayName` domain model: exact NFC bytes, no surrounding whitespace, controls, illegal scalars, or directional formatting controls. The table cascades with the device tombstone, contains no remote authority, and is never populated from pairing, discovery, or another remote payload. Setting it is an authenticated local-administration transaction that inserts `device.displayNameConfirmed`; a revoked device cannot be renamed. Interactive Control admission fails while the current device has no confirmed name.

`pairing_consumptions` permanently binds a random pairing ID to the device ID created from it and records the non-negative consumption wall time. The row has no foreign key to the retained device tombstone: deleting an expired revoked-device row must not make a previously consumed pairing ID reusable. The one-time secret, nonces, authentication string, and QR payload are never stored in this table.

`durable_operations` contains the UUID operation identity, device/client UUIDs, exact 32-byte request-binding digest, closed lifecycle state, bounded capability/provider identifiers, schema and provider revisions, authorization/grant/policy revisions, required host state, expiry, timestamps, and an optional bounded stable terminal code. It never contains raw parameters, provider results, screen/input content, filesystem paths, credentials, or arbitrary error text. The exact digest construction is `spec/capability-protocol/v0/operation-binding.md`.

At most 10,000 operation rows are retained per device. A duplicate operation UUID with the same digest returns the existing row without a second event; a different digest fails closed. Hitting the quota rejects new work and leaves every retained row unchanged. Only terminal rows at least 30 days old may be purged. The device foreign key prevents tombstone removal while retained operation rows still refer to it.

`security_events` contains bounded host-owned event kinds and identifiers only. Schema v7 registers host establishment/certificate replacement/recovery fencing/replacement, pairing commit, device state transitions and local display-name confirmation, operation admission/claim/transition/recovery, and stable operation failure kinds. Security-event insertion is part of the same transaction as the state it describes; a caller never reports durable success when either half fails.

Detailed user-visible history uses the independently quota-bounded database in
`spec/audit/v0/README.md`. It never replaces the transactional minimal event or
becomes authority for security state. Its closed schema, scoped gap metadata,
required-before-effect writes, compaction, and self-filtering prevent audit
growth or another device's activity from leaking through `audit.readSelf`.

`security_control` is a singleton for database health metadata. It is not the emergency deny latch and must never be used as one.

`status_sequence` is an optional singleton containing the current status generation UUID, next revision, and exhaustion bit. A status response is not returned until a compare-and-swap from the authority's expected sequence to its replacement commits. Sampling or commit failure consumes no revision; a successful commit may consume a revision even if the later network send fails.

## 4. Transaction invariants

- Pairing storage accepts only the initial `activeMonitorOnly`, authorization epoch 1, grant revision 1, and positive policy revision record, with both public keys exactly 65 bytes and no remote Act/Control grants.
- Pairing-ID consumption, device creation, and the minimal pairing event are one transaction. A duplicate pairing ID is rejected before device mutation, and any fault rolls back all three records.
- First-install bootstrap persists its candidate host UUID and exact Keychain tag before key creation. Completion accepts only that exact pair and atomically consumes the bootstrap row with ready identity establishment and its event. Any completion fault leaves the pending row intact and publishes neither identity nor event.
- Host-identity recovery begins with one transaction that first compares the exact locally reviewed host UUID and fingerprint, stores the exact bounded reviewed intent, changes every non-revoked device to `revoked`, advances its epoch and grant revision, deletes its grants, changes the host singleton to `fencedForReplacement`, binds the same recovery UUID, and inserts the minimal fence event. A stale expected identity conflicts before mutation; any fault restores the ready host identity and every device row and leaves no intent.
- Repeating recovery while fenced is idempotent only when every intent field is exactly equal; a different command, review, recovery UUID, cause, time, or expected identity conflicts. Completion requires the same durable recovery UUID plus a different host UUID, key tag, and fingerprint. Completion replaces the host singleton, inserts its event, and stores the last-recovery receipt atomically while retaining the exact intent, but never reactivates old device tombstones. A retry matching that completed intent returns `alreadyCompleted` and never fences the replacement identity; the recovery UUID alone is insufficient.
- Keychain work never occurs inside the SQLite transaction. A replacement key is tagged by recovery UUID outside the database; a crash before completion resumes denial and the same fenced workflow rather than clearing it.
- Every grant change, suspend, resume, or revoke advances the authorization epoch according to `CompanionDomain`.
- Grant sets are canonical sorted lists of at most 256 unique closed capability identifiers. Pairing starts empty. A replacement or reviewed resume atomically replaces every row, advances the grant revision and authorization epoch, updates device state, fences admitted work under the old revisions, and inserts one bounded event. An identical active grant set is idempotent and advances nothing.
- Suspend or revoke atomically denies pre-policy/approval work, fails queued work as `operation.authorizationRevoked`, and moves running work to `cancelRequested`. Revoke also changes the device to `revoked` and removes all grants before commit.
- Operation admission inserts the bounded record and event in one transaction. Provider code never runs before a second transaction revalidates the active-granted device, client, epoch, grant, policy, provider generation/execution revision, exact host state, and expiry and changes `queued` to `running`.
- A stale execution claim changes `queued` to `failed` with a stable bounded code in the same transaction. On startup, the coordinator changes every `running` or `cancelRequested` row to `outcomeUnknown` before accepting remote work; queued work remains queued for fresh revalidation and is never implicitly retried.
- A fault after row mutation but before event insertion or commit rolls back the entire change.
- Revocation pre-arms the independent deny latch before opening its SQLite transaction. A failed transaction leaves the latch active and returns failure to the local coordinator, which closes remote work; retrying or treating an in-memory state as durable is forbidden.
- Revoked identity never becomes active. Tombstone expiry may delete the retained device row only through its explicit domain transition and retention policy.

## 5. Stage 0 evidence

Before this profile can back pairing or remote startup:

1. Fresh database creation and every supported migration pass.
2. Future-version and corrupt databases are refused without replacement.
3. Atomic host establishment/recovery intent, fencing, replacement, exact restart/receipt replay, pairing consumption/device/event, device transitions, durable operation admission, and execution claim tests prove rollback at each injected fault point and permanent replay denial.
4. Epoch and grant revisions fail closed at the safe-integer limit.
5. Operation tests prove same-digest replay, different-digest conflict, no quota eviction, exact claim fencing, suspend/revoke cancellation, 30-day terminal retention, and restart `outcomeUnknown` behavior.
6. Disk-full tests cover WAL creation, transaction commit, checkpoint, and restart.
7. The independent emergency latch passes preallocation, torn-write, `fsync`, disk-full, restart, clear-after-repair, and dual-corruption tests.
8. Stable-Xcode release targets prove ownership, permissions, backup behavior, update/rollback, and complete uninstall on clean users.
