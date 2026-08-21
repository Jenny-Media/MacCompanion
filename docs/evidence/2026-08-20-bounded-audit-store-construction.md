# Bounded audit store construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

`SQLiteBoundedAuditStoreV0` is a separate detailed-history authority with a
closed content-free event schema. It allocates durable safe-integer sequences,
pages newest-first, filters remote self history by authenticated device scope,
and exposes scope-specific pruning/drop gaps without revealing another device's
activity.

The production configuration enforces 16 MiB logical bytes, 50,000 rows,
30-day retention, 1,024-byte records, 100-row pages, and 120 attempts per actor
plus subject-device bucket per minute. Compaction removes expired rows and then
the oldest best-effort rows. Unexpired required-before-effect rows are never
quota-evicted; required rate/quota/storage failures fail closed. A best-effort
drop is reported only after its gap counter commits.

The detailed database does not replace the minimal `security_events` rows that
remain transactionally coupled to security-state mutations.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

## Result

The public validation gate passed with 51 authoritative fixtures and 592 Swift
tests, including the 12 audit tests. It also compile-checked the macOS and iOS
UI/platform targets, both Network-platform targets, and all three
no-prompt/no-network probes. SwiftPM emitted only its expected read-only
user-cache warnings in the sandbox.

## Focused evidence

Twelve tests cover model contradictions, global privacy, append/cursor/restart
ordering, duplicate IDs, exact requesting-device filtering, per-device gap
isolation, row and logical-byte compaction, required-row preservation,
best-effort quota/rate drops, age retention, every injected transaction fault,
future schemas, invalid pages, and terminal sequence exhaustion.

## Follow-on composition

The store is now wired to the authenticated, exact-current-grant
`audit.readSelf` package path documented in
`2026-08-20-audit-self-wire-composition.md`. Audit producers, local history UI,
and rendered client history remain separate slices.

## Boundary not claimed

Real WAL/checkpoint/disk-full exhaustion, file ownership/protection, corruption
repair UX, seven-day measurements, signed authenticated adapters, and rendered
history UI remain release-shaped evidence.
