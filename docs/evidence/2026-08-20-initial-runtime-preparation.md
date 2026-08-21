# Initial Interactive runtime preparation evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

`InteractiveSessionBootstrap` now retains the exact
`InteractiveApprovalEffects` consumed from the phone's verified approval
signature and exposes a closed projection to runtime interaction classes. The
initial runtime path no longer needs to infer or default lease authority from
unverified request data.

The durable-plus-visible admission snapshot also retains the exact nonzero
menu-app generation/revision that bracketed the SQLite device/grant read.
`InteractiveInitialRuntimeCommandAuthorityV1` consumes that snapshot, the
verified bootstrap, and one sanitized Desktop descriptor. It:

- requires one eligible device/grant/host/menu/display binding;
- requires session, epoch, Desktop revisions, and approved classes to match;
- issues renewal counter zero with fresh command/lease IDs;
- bounds expiry to the earliest of ten seconds, session deadline, and
  descriptor deadline;
- validates the install receipt against the exact command and admitted menu
  generation with a non-regressed revision;
- advances `starting` to `activeUnlocked` only after that receipt;
- returns exact preparation replay but rejects conflicting reuse; and
- invalidates unused role credentials and enters `teardownRequired` for an
  ambiguous, late, stale, or cross-generation receipt.

The installed bootstrap is transferred once; the preparation authority cannot
release it again.

## Verification

Four new focused tests prove exact approved-effect binding, deterministic
prepare replay and one-time transfer, earliest-deadline lease construction,
cross-generation receipt teardown, and descriptor authority-widening denial.
Existing dispatcher and SQLite-admission tests continue to cover stable/torn
visible joins, approval/runtime races, required audit, and disconnect
compensation.

The complete public validation gate passed with:

- 60 indexed protocol/product fixtures;
- 663 repository files, 34 historical paths, and 14 repository-material
  fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 895 Swift tests, including 162 `CompanionAgent` tests;
- all iOS Simulator client-platform/client-UI and macOS local-authority compile
  gates; and
- all three no-prompt/no-network platform probes.

Only expected read-only SwiftPM user-cache warnings were emitted.

## Boundary not claimed

This authority intentionally performs no IPC. A future signed bridge must
serialize the last durable/visible admission read with authenticated menu-app
XPC installation, retain the transferred channel/session authorities, and
drive four-effect teardown whenever preparation reports
`teardownRequired`. No physical TCC, capture, input, indicator, post-event, or
final-identity evidence is claimed here.
