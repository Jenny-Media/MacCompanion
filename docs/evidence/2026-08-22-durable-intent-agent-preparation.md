# Durable-intent-ordered Agent preparation

Date: 2026-08-22

## Claim

`MacAgentApplicationPreparationFacadeV1` loads one canonical durable remote-
access intent before constructing the Agent's primary startup inputs, then
retains a ready prepared product behind an activation-inert owner with only
snapshot and terminal-finish operations.

## Construction

- Release storage now names a dedicated
  `remote-access-intent-v1` subdirectory. The atomic single-record intent store
  cannot be pointed at the broader release root, whose database and latch files
  it would correctly reject as unknown content.
- Preparation checks cancellation, constructs one release storage authority,
  constructs the intent store at that exact subdirectory, loads durable intent,
  creates an ambiguous lifecycle state, constructs primary inputs from that
  exact state, and only then invokes host-identity/product preparation.
- The facade requires both the constructed primary inputs and a ready prepared
  root's canonical lifecycle snapshot to preserve that exact durable state at
  revision zero with both observation epochs zero. A mismatch fails closed,
  and a mismatched prepared root is retired before the error escapes.
- An absent intent is disabled with Agent and menu stopped. An enabled intent
  restores both processes only as starting. The console state is always
  `otherConsoleUserActive`; neither state exposes Observe, local administration,
  or new Interactive Control before fresh readiness and positive session proof.
- The preparation validator accepts only the exact disabled/stopped or
  enabled/starting ambiguous states and rejects active, locked, logged-out,
  ready, availability-publishing, or otherwise inconsistent initial states.
- The existing product bootstrap now has a storage-accepting production seam.
  Its ordinary public entry point preserves immediate composition, while the
  preparation facade uses the inert variant that defers readiness-producing
  local-XPC construction until explicit package-owned activation. Both variants
  retain one canonical menu-loss composition rather than duplicating it.
- A ready product becomes `MacAgentInertApplicationLifecycleV1`. It exposes
  host identity, storage paths, the canonical content-free primary lifecycle
  snapshot, and
  idempotent finish only. The raw prepared product, local-XPC start, listener,
  network composition, menu surface, registry, providers, and primary services
  do not escape.
- Cancellation after a prepared root exists awaits terminal compensation before
  propagating. Concurrent finish joins one task. Deinitialization begins
  best-effort retirement, while explicit awaited `finish()` remains the process
  contract.

This checkpoint is activation-inert, not persistence-inert. If the public
production entry point is called, release storage, security databases, the
deny latch, and durable host identity may be created or reconciled. The inert
path does not invoke the local-XPC factory, even during terminal finish. Durable
artifacts are preserved for the next launch after failure or cancellation;
they are not silently deleted or redirected.

## Deterministic verification

The focused preparation/lifecycle matrix proves:

1. Exact storage → intent-store → intent-read → primary-input → prepared-root
   ordering, including the dedicated intent path.
2. Safe-disabled absence and enabled-but-ambiguous starting restoration with no
   readiness or positive session authority.
3. An inert prepared snapshot, zero request-context observer start, concurrent
   finish joining, terminal request contexts and owner retirement, and one
   prepared-root retirement while canonical lifecycle state remains unchanged.
4. Cancellation during an intent read prevents root preparation; cancellation
   after a ready root compensates exactly once.
5. First-unlock, local-recovery, and recovery-fenced outcomes map without a
   prepared authority.
6. The exact intent directory reopens across release-storage preparations and
   restores the same durable enabled intent.
7. Owner deinitialization starts deterministic best-effort prepared-root
   retirement.
8. Every invalid initial lifecycle class is rejected by a complete matrix.
9. Production-shaped inert preparation leaves both disabled/stopped and
   enabled/starting canonical primary lifecycle states unchanged, never invokes
   the local-XPC factory, and does not consume the prepared primary root.
10. Adversarial primary-input and returned-prepared-root state, revision, and
    observation-epoch substitution fail closed, with exact retirement of every
    mismatched prepared root.
11. Explicit deferred activation constructs and starts one local-XPC product;
    start failure and first or joined caller cancellation during a suspended
    late start terminally clean up, and canceled activation cannot report
    success.

Focused command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
CompanionAgentProductPlatformTests
```

Result: all 34 ProductPlatform tests passed.

`swift test list` reports 1,328 unique package tests with no duplicate names.

The complete repository gate passed:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/bin/bash scripts/validate.sh
```

Result: 64 indexed JSON fixtures, 925 repository files, 1,124 historical
blob-paths, 14 repository-material fixtures, four Swift package manifests, 12
dependency-policy fixtures, permanent Apple-target policy, 302 production
Swift source files, 1,328 package tests, every supported cross-build, and all
8 platform-probe tests passed on Xcode 27 beta.

The checked-in Xcode project also built the code-signing-disabled Debug app
and embedded Agent:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project MacCompanion.xcodeproj -scheme MacCompanion \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Result: `** BUILD SUCCEEDED **`; the output contains the outer app executable,
embedded `MacCompanionAgent`, and `media.jenny.maccompanion.agent.plist`. The
1.6 GB regenerable SwiftPM `.build` cache was removed after the complete gate
to make room. This is unsigned construction evidence, not signed runtime,
Keychain, entitlement, or launch evidence.

## Non-claims

Neither permanent target imports or invokes this facade. This checkpoint does
not start the conservative context observer or construct local XPC, a network
listener, Bonjour, pairing, a process, or login-role mutation; it publishes no
readiness
and enables no Observe, Act, or Interactive Control route. It does not prove
Keychain access, reciprocal XPC authentication, networking, lifecycle recovery,
signing, or physical behavior from the permanent Agent process.
