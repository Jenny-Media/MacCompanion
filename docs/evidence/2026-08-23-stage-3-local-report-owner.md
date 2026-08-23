# Stage 3 local report owner

Date: 2026-08-23

## Outcome

The permanent iOS product now owns the local Stage 3 study-report boundary
defined by [ADR-0002](../adr/0002-stage-3-product-evidence.md). The
`CompanionStudy` module provides one bounded atomic report store and a separate
owner for save, exact preview, explicit export, and destructive deletion. The
package-owned iOS UI exposes those operations from the permanent application
without requiring a pairing, Observe, Act, or Control session.

This checkpoint adds no telemetry, account, relay, uploader, background
transfer, or recipient. The app remains usable when no report exists and when
the user never exports one.

## Durable local boundary

`AtomicFileStage3StudyReportStoreV1` stores exactly one canonical report in an
app-owned directory. It:

- accepts only the existing strict 256-KiB-bounded report codec;
- applies private 0700 directory and 0600 file permissions;
- rejects symlinks, unexpected visible entries, malformed pending names,
  unsafe file types, nonprivate files, and oversized or invalid reports;
- serializes readers and writers with an advisory file lock;
- writes a same-directory temporary file, synchronizes it, renames it over the
  current report, and synchronizes the directory;
- uses exact-current revision fencing for replacement and deletion; and
- converges idempotently when a caller retries after an injected post-rename
  or post-delete ambiguity.

Startup removes only well-formed bounded `.pending-<uuid>` files and refuses
unknown material. It does not treat an arbitrary directory as trusted storage.

The permanent iOS storage composition places the report beneath the existing
private Application Support root. At construction, that tree is verified as
non-symlinked, set to `completeUntilFirstUserAuthentication`, excluded from
backup, and restricted to owner-only POSIX access. New report files are created
inside that protected directory. This is source and Simulator-build evidence;
the final file attributes and behavior before first unlock and after relock
remain a signed physical-device proof.

## Preview, export, and deletion authority

`Stage3StudyLocalReportOwnerV1` keeps export separate from storage:

1. The user requests a preview of the exact canonical JSON.
2. The owner returns that JSON and a private one-use token without creating an
   export payload or file.
3. A second explicit action must present the matching token.
4. The owner rereads durable state and refuses export if the report changed.
5. The iOS system file exporter then lets the user choose the destination.

The token is consumed on the export attempt and is invalidated by owner saves.
There is no silent retry. Deletion requires an explicit destructive UI
confirmation and the exact visible study code; a stale or different report is
not removed.

The permanent iOS application exposes a persistent Study Report toolbar action
after protected storage opens. The screen truthfully distinguishes loading,
no-report, ready, exact-preview, and failure states. It never claims that a
report was captured merely because the storage/UI exists.

## Verification

Six new focused tests cover:

- insert, replace, reopen, permissions, and delete;
- stale writers and cross-study replacement rejection;
- pre-rename, post-rename, and post-delete ambiguity convergence;
- unknown files and report symlink rejection;
- fresh one-use preview tokens and stale-preview refusal; and
- exact-study-code destructive deletion.

The focused `CompanionStudyTests` suite passes 18 tests:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path Packages/MacCompanionKit \
  --filter CompanionStudyTests
```

The package-level iOS client UI cross-build passes, and the permanent
`MacCompanionIOS` application target builds for the generic iOS Simulator on
Xcode 27 beta with signing disabled:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project MacCompanion.xcodeproj \
  -scheme MacCompanionIOS \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The complete repository gate also passes 1,629 MacCompanionKit Swift tests,
eight platform-probe tests, all policy and release fixtures, every supported
cross-build, 1,215 current repository files, and 2,241 historical blob paths.

## Non-claims and next gate

This checkpoint does not enroll a tester, create a report, connect visible
product outcomes to report facts, obtain participant consent, export to a real
destination, or prove Data Protection and UI behavior on a physical device. It
does not supply calibration or confirmatory evidence and makes no market-MVP
claim.

The later
[local enrollment and initial capture](2026-08-23-stage-3-local-enrollment-capture.md)
adds dogfood-only enrollment, explicit day sessions, and initial
pairing/connection/Observe bindings. Internal dogfood must still compare every
recorded denial, failure, `outcomeUnknown`, fallback, Stop, revocation,
recovery, and completed job against visible product truth before any external
cohort begins.
