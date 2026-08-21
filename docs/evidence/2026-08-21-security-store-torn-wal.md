# Security-store torn-WAL recovery evidence

Date: 2026-08-21

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

`tornWALTailNeverPublishesAPartialPairingTransaction` exercises SQLite's real
WAL recovery against the production schema and store. It is not an injected
Swift transaction fault.

The test first closes a store containing one fully checkpointed pairing. It
then reopens the store, commits a second pairing, and deliberately keeps that
connection live so the second transaction remains in the WAL rather than the
main database. With writes idle, it clones the main database and WAL into
three secure case directories and truncates 1 byte, 64 bytes, and half of the
WAL tail respectively.

## Safety invariant

Each cloned store may do only one of two things:

- refuse recovery with a non-success SQLite error; or
- open with the original checkpointed pairing intact and expose the candidate
  pairing as one whole transaction or not at all.

Whole visibility means the candidate device, one-time pairing consumption,
active-device count, and minimal security-event count all agree. The test also
requires at least one truncation to reject or roll back the candidate, proving
that the matrix materially damages transaction evidence instead of exercising
three harmless suffixes.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --disable-sandbox \
  --package-path Packages/MacCompanionKit \
  --filter tornWALTailNeverPublishesAPartialPairingTransaction
```

## Result

The three-boundary matrix passed. The complete persistence target subsequently
passed with 64 tests, and the repository-wide hardened gate passed with 63
authoritative fixtures, 765 repository files, and 1,035 Swift tests.

## Boundary not claimed

The source connection remains live and idle while its files are cloned; this
is a deterministic crash-artifact construction, not a killed child process or
power-loss experiment. Main-database page tears, directory-entry loss,
simultaneous physical-volume exhaustion, filesystem/hardware fault injection,
and signed release-volume recovery remain open.
