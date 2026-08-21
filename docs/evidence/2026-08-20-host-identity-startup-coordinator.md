# Host-identity startup coordinator evidence — 2026-08-20

## Claim

The bundle-independent macOS platform graph now has a recoverable host-identity
startup boundary. Before any pending Keychain creation, schema v7 persists one
candidate host UUID and exact bounded application tag. Restart adopts that row.
Ready publication atomically inserts the matching established identity, deletes
the candidate, and records `hostIdentity.established`.

The public coordinator constructs the Security.framework custody authority from
the release application-tag configuration. It can:

- create or resume only the exact durable tag;
- reconstruct the listener `SecIdentity` from an unchanged valid certificate;
- replace a missing, invalid, expired, or wrong-key certificate only around the
  established key and fingerprint, under a complete-row stale-write fence;
- wait without rotation before first unlock;
- return explicit established-key-loss and recovery-fenced outcomes without
  opening listener authority.

No private-key bytes, route, certificate, fingerprint, or remote value enters
the bootstrap singleton. Keychain mutation remains outside SQLite transactions.

## Automated evidence

Fourteen new tests cover:

- empty v4-to-v5 migration and failed candidate-commit rollback;
- exact-candidate adoption, mismatch/bypass rejection, and completion rollback
  at every injected persistence fault;
- same-key certificate replacement and stale/fault rollback;
- first bootstrap, ready restart without rotation, crash after certificate
  issuance followed by exact-tag/key resume, pending and established
  first-unlock waiting, missing established-key recovery, invalid-certificate
  same-key repair, and recovery-fenced denial.

The complete unsigned repository gate validates 60 indexed fixtures, repository
and dependency policies, privacy manifests, SBOM/release evidence, 915 Swift
tests, both platform cross-compiles, and three no-network/no-prompt probes.

## Deliberate limits

This is not final signed Keychain/Secure Enclave evidence. The final application
tag prefix/access group, designated-requirement topology, physical first-unlock
behavior, live listener use, locally confirmed destructive recovery, and
uninstall retention/reset behavior remain release-identity or physical gates.
