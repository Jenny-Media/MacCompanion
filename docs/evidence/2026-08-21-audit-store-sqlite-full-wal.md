# Detailed-audit SQLite full and WAL recovery evidence

Date: 2026-08-21

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

`SQLiteBoundedAuditStoreV0` now accepts the same optional validated
`maximumPageCount` policy as the security store. It applies the limit to its
own SQLite connection after migration, preserves the existing default when no
limit is supplied, and refuses a configured ceiling below current usage.

This physical page ceiling is independent of the store's existing 16 MiB
logical quota, retained-row limit, retention policy, and rate buckets. It lets
the production transaction path encounter SQLite's actual `SQLITE_FULL`
result.

## Proof

`realSQLiteFullRollsBackAuditRowsAndRecoversAfterCheckpoint` seeds a schema-v1
WAL database, truncates the WAL, and reopens the production store at its exact
current page count. It appends unique best-effort records until SQLite returns
`SQLITE_FULL`, then requires all previously committed records to remain
readable while the rejected event, sequence advance, rate attempt, and gap
metadata are absent.

That absence is deliberate: the API must not report a best-effort drop as
durable when the same full pager prevented its gap metadata from committing.
An exact required-before-effect event is then also rejected with
`SQLITE_FULL`, and the complete externally readable page remains byte-for-value
unchanged.

After closing the store, the test performs a real truncating WAL checkpoint,
requires `PRAGMA integrity_check` to return exactly `ok`, and reopens with 128
additional pages. The exact rejected best-effort and required events then
commit at the next two contiguous sequences.

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

All 61 `CompanionPersistenceTests` passed, including both real pager-full
stores. The repository-wide hardened gate subsequently passed with 63
authoritative fixtures and 1,032 Swift tests.

## Boundary not claimed

The page ceiling exercises real SQLite allocation and WAL behavior, but it is
not a physically full APFS volume. Simultaneous volume exhaustion across the
security store, detailed-audit store, and preallocated deny latch; torn writes;
Keychain/database crash ordering; signed-bundle ownership and Data Protection;
repair UX; and stable-toolchain release evidence remain open.
