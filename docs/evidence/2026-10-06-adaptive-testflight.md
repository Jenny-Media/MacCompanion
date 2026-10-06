# Adaptive desktop and Terminal internal TestFlight — 2026-10-06

## Scope and source

The user authorized committing the current changes and releasing a new internal
TestFlight version. Source commit `ef90c1e26eb118470fbec5d88fc7e1a913754248`
contains adaptive desktop/login/session controls, viewport continuity, Duo
tabletop input, fullscreen Terminal and compact landscape Terminal login.
The product remains one direct iOS client using built-in macOS Screen Sharing
and optional Remote Login, with no Mac helper installation.

## Verification

- Stable Xcode 27.0 and Xcode 27.1 RC hosted QA each passed 121 tests with five
  opt-in capture tests skipped and zero failures. OpenSSH interoperability passed.
- Required stable `bash scripts/validate.sh` passed before upload. The first
  invocation failed at the legacy selected-context test's live-display metadata
  assertion; its isolated rerun and the full rerun passed without source changes.
  Logs are outside Git under `/private/tmp/maccompanion-testflight-20261006-*`.
- The normal stable-Xcode device build passed. The internal archive uses
  Xcode 27.1 RC (`27A9275`, SDK 27.1) to include guarded Duo reserved-region and
  hinge APIs. Its deployment floor remains iOS 26.0. RC results remain provisional;
  physical Duo, actual Split View and this exact build's physical acceptance
  remain separate checks.
- The corrected local comparison contains 34 before/after pairs, including full
  production Terminal, keyboard/fullscreen and regular iPhone landscape captures.
  Images and provenance remain outside Git.

## Archive and upload

The optimized **1.0 (4)** archive excludes DEBUG and experimental sources.
Existing app/widget IDs, Apple Distribution certificate, exact App Store
profiles and private Keychain groups are preserved. Exact source hashes, app and
widget entitlements, disabled debugging and strict deep signatures verify.
Signed application binary SHA-256:
`5b0f4fa945aa90329a30f0ee7612186f1d4b80fb0a933b2b7eb11eb5459fe915`.

Archive, source-bound report, upload options and logs are outside Git under
`/private/tmp/maccompanion-adaptive-testflight-20261006/`.
Xcode's internal-only export/upload completed successfully at 15:33
America/New_York. App Store Connect independently confirmed processing, then
completed it as build `df7e85f5-f006-452e-83e3-e5997d1ea8e2`.
The existing missing OpenSSL dSYM warning is non-blocking; app/widget symbols
are included. No new certificate, account access or provisioning identity was
created.

## Distribution state

The unchanged standard-encryption selection and previously authorized
outside-France beta answer were reviewed and saved. Focused What to Test notes
cover login, keyboard, fullscreen Terminal, viewport/session continuity,
press-and-slide and Duo tabletop behavior.

The existing Internal Testing group is assigned to build 4. Its Builds page
confirms **1.0 (4), Internal, Testing**, expiring in 90 days, with one existing
tester and four total builds. The tester has installed the previous build 3;
this is not acceptance of build 4. Availability proof is saved outside Git as
`maccompanion-testflight-build-4-testing.jpg` under the task's visualization root.
No external beta or App Store release occurred. The dependency graph remains
`releaseAdmitted = false`.
