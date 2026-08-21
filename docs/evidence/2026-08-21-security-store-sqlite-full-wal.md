# Security-store SQLite full and WAL recovery evidence

Date: 2026-08-21

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

`SQLiteSecurityStore` now accepts an optional validated `maximumPageCount`
policy. The default remains SQLite's platform maximum. A configured store
applies the cap to its own pager after migration and refuses startup when an
existing database already uses more pages than the requested cap.

The policy provides a deterministic way to exercise SQLite's real storage-full
path without replacing the database implementation or translating an injected
Swift error into a storage error.

## Proof

`realSQLiteFullRollsBackPairingAndRecoversAfterCheckpoint` creates and seeds a
schema-v7 WAL database, truncates its WAL, reads the resulting page count, and
reopens the production store with that exact page count as its hard ceiling.
It then drives the ordinary `commitPairing` transaction until SQLite itself
returns `SQLITE_FULL`.

After the rejected commit, reads through the still-open store prove that:

- the active-device and minimal-security-event counts include only successful
  transactions;
- the rejected device row is absent; and
- the rejected one-time pairing-consumption row is absent.

The test then closes the store, runs a real truncating WAL checkpoint, requires
`PRAGMA integrity_check` to return exactly `ok`, and reopens the same database
with 128 additional pages. The exact previously rejected pairing transaction
then commits and all three durable facts advance together. The same test also
proves that a configured cap below current page usage is rejected at startup.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --disable-sandbox \
  --package-path Packages/MacCompanionKit \
  --filter CompanionPersistenceTests
```

## Result

All 60 `CompanionPersistenceTests` passed, including the real pager-full,
rollback, checkpoint, integrity, capacity-recovery, and resumed-mutation proof.
The repository-wide hardened gate subsequently passed with 63 authoritative
fixtures and 1,031 Swift tests.

## Boundary not claimed

This is actual SQLite `SQLITE_FULL` and WAL behavior under a connection-local
page ceiling; it is not a claim about a physically full APFS volume or torn
filesystem writes. Volume-wide exhaustion across the separate detailed-audit
database and deny latch, Keychain/database crash ordering, file ownership and
Data Protection in signed bundles, corruption repair UX, and stable-toolchain
release evidence remain open.
