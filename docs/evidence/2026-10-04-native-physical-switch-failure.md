# Physical view-switch failure investigation

Status: the latest physical attempt establishes a fatal post-update content
placement rejection in the native capture adapter. The same rejection is
reproduced in a native regression; a bounded placement-discard repair passes
the native tests and final full stable validation. The repaired normal Mac host
is installed and launched; physical acceptance is tracked below. Earlier selected-surface lookup and input rejection
attempts remain separate, unresolved cases.

## Installed baseline and evidence

The reported iPhone 18 Pro Max session uses the normal installed products.
The installed Mac executable and native-host catalog still match source
`0609a0b1f5db7dc94e234c412b2a5c77abbe55550b33f39225a7fa702d34f77c`:
executable SHA-256 `939baacb461e5a2bbc6e251d340e29180db271dd030d82f840350a306be678bd`,
catalog SHA-256 `3cd7a967d9c118cecd7ecab5efb7296ef6f4013e6046de6039470766ece177f3`.
The running main app and Agent belong to the installed bundle. The phone's
installed application URL matches the successful installation receipt for this
candidate. Its content-free runtime journal was retrieved without launching,
updating, re-pairing or resetting the phone.

Private evidence remains under `/private/tmp`, with prefix
`maccompanion-physical-failure-20261004`: `ios-runtime.log`,
`host-last3h.ndjson`, `installed-phone-app.json` and `ios-log-copy.json`.
No raw logs, identities, captures or input content are added to the repository.

## Two observed failure paths

Times below use America/New_York on 2026-10-04.

1. **Input rejection after a completed switch.** At 10:34:12.272 the phone
   records fresh input admission for a retained switch completed in 1,707 ms.
   At 10:34:15.868 the Mac records input sequence 8 rejected as
   `platformActionFailed`. The Agent then retires Interactive roles and the
   primary fails with `admissionChanged`. The phone reports an invalid media
   read and terminal Control failure. The existing runtime error conversion
   discards the specific input posting or release error, so this log does not
   prove which input check originally failed. The input kind is privacy-masked;
   no pointer movement or click is inferred from sequence 8 alone.
2. **Native preparation failure during a later switch.** A fresh Control
   session completes retained switches in 788 ms and 1,300 ms. The next
   switch is fenced at 10:34:46.053 and host-acknowledged at 10:34:46.690.
   The phone records a server-notified native termination at 10:34:46.817,
   before recording native preparation or a fresh frame for that switch.
   The Mac records local native backend operation 1083 failing as
   `unavailable` at 10:34:47.704, followed by Interactive and primary teardown.
   The phone's transition is cancelled after 1,754 ms. The logged command
   error follows owned cleanup; its timestamp alone does not identify the
   check that initiated native retirement.

These are physical runtime failures. The earlier 202-switch Simulator pass
remains valid for that test journey but does not establish physical reliability.
Its final input effects were synthetic; it did not exercise actual macOS event
posting and selected-window activation. Repeating that same test cannot settle
the input rejection observed here.

## Source-backed candidates, not established causes

- Capture evidence expires after two seconds. Input posting requires current
  evidence; idle or blank ScreenCaptureKit samples are ignored before the frame
  callback. A static surface could therefore leave input evidence stale. The
  failing physical log does not contain the evidence age or original rejection.
- A trackpad tap sends button down/up without first moving the Mac pointer.
  Native event construction rejects a click if that pointer is outside the
  selected display. This boundary has deterministic tests, but the failed
  physical input kind and pointer location are not known.
- Replacement preparation revalidates display, selected-window identity,
  snapshot, geometry and capture ownership. The original `unavailable` result
  merges those rejecting paths; it cannot identify which check failed.

The observed session-wide retirement follows the existing input/XPC failure
policy. That explains how one failure turns into a blank client and unavailable
Control, but does not prove which condition first triggered it. These candidates
must be distinguished with a fresh installed-app attempt before choosing a repair.

## Diagnostic follow-up

Live host and closed native-child code collection were prepared for a fresh
physical attempt. The initial bounded child collection saw no new attempt.
macOS refused debugger attachment to the installed main process; no debugger
breakpoints were installed and no protection was disabled.

A diagnostic-only Mac source candidate adds failure-only, indexed local stages
and closed error reasons before the existing errors are propagated. It records
the underlying input activation/posting/construction failure, the native command
stage and observed phase, and the reason capture evidence is unavailable.
Unknown errors remain `unclassified`; arbitrary descriptions, window metadata,
input, identities and credentials are excluded. The existing checks, error
conversion, deadlines, retirement, input fencing, protocol and native engine
remain unchanged. The normative local-backend document and its sole indexed
fixture were updated before this instrumentation.

Diagnostic source SHA-256:
`9fbc94ce94474e8f1b1f31875ca0dce6eb1240522e60e1212b6f85e8eeb19c89`.
Privacy vocabulary, unknown-error non-disclosure, the 32-iteration joined
retirement regression and existing pointer-construction rejection tests pass.
The diagnostic normal Mac build passes. Required `bash scripts/validate.sh`
passes under stable Xcode 27.0 (27A266a), with 125 indexed fixtures. An earlier
run of the final source failed the existing receiver test's immediate release
assertion after observing a reply; the complete rerun passes without source or
test changes. That failed run is retained rather than counted as a pass.

The signed diagnostic normal Mac app is installed and launched. Its executable
SHA-256 is `a5cd0e1bc56f2af6612f1ce38c2bcd623f3d5eef0cfb154e32d4dfab704f6027`.
Existing entitlements, designated requirements, development profile and native
host catalog are verified unchanged. Both old owned Mac processes were stopped;
the new main app and Agent run from the installed bundle, and the Agent's TLS
listener reaches ready. The previous complete bundle is retained for rollback.
Pairing storage and the existing phone build were not replaced.

Private final validation/build logs use suffixes
`diagnostic-stable-validation-final-retry.log` and
`diagnostic-mac-build-final-v2.log`. The signed installation receipt is
`/private/tmp/maccompanion-physical-failure-diagnostic-final-mac-install-20261004.json`.
Earlier compiler, validation and superseded staging artifacts remain separate.
The phone-journal read immediately after installation still ended at the original
10:34 failure. At that point iPhone Mirroring requested that the affected
phone be physically unlocked before it can be used for the diagnostic attempt.

Local subsystem-only log reads also include deliberately failing test processes.
Those records are excluded from physical-failure evidence by executable path;
test diagnostics must not be mistaken for an installed-app failure.

## First diagnostic physical retry

The user reports another failure. A fresh phone journal and installed-process
Mac logs capture the attempt at 11:34–11:35, using the diagnostic source above.
The installed executable hash still matches its signed installation receipt.
Private evidence is `maccompanion-physical-failure-20261004-` followed by
`ios-runtime-diagnostic-failure-1.log`, `host-diagnostic-failure-1.ndjson` and
`ios-copy-diagnostic-failure-1.json`. The bounded native-child code collector
contains no capture error code; its empty result is not a passing capture test.

Four retained transitions reach video and input readiness in 1,131, 721, 1,397
and 2,121 ms. The next transition begins at 11:35:31.616 and the phone records
host acknowledgement at 11:35:32.375. Before that phone observation, the Mac
records at 11:35:32.365:
`native-command-rejected operation=prepareReplacement stage=read-selection reason=local.unavailable`.
The phone records server-notified native termination at 11:35:32.469, before
native preparation or a new presentation for this transition. Joined cleanup
finishes before the generic XPC failure is logged at 11:35:33.383; the primary
then closes with `admissionChanged` at 11:35:33.417. The phone's transition is
cancelled after 1,869 ms.

This observed initiating rejection is in the normal Mac selected-surface lookup,
before `configureRetainedReplacement` or `backend.prepare` is called. The native
engine cannot receive the new target after this rejection. Input-posting,
capture-evidence freshness and encoder packet handling are not the initiating
failure in this attempt. The previous input rejection remains a separate case.

`readSelectedCapture` still merges admission closure, committed-surface/scope
validation, geometry projection and live selected-window/application validation
into `local.unavailable`. The exact subcheck is not established. A further
diagnostic-only candidate names each existing failed check with a closed indexed
code; comparisons, thrown errors and validation order are preserved. No functional
repair is selected on the basis of the broad `read-selection` result.

iPhone Mirroring initially times out after setup, then connects successfully.
The earlier read-only passcode-state query does not establish why it timed out.
No authentication or phone-lock setting is changed.

The refined diagnostic source is
`e62f99408b137ae66cfe02b98f09113207418005ca32a109cda89d7c18f9c908`.
Six focused tests pass, including four selected-geometry cases and the sole
indexed closed diagnostic vocabulary. Required `bash scripts/validate.sh` and
the normal Mac build pass under stable Xcode 27.0. The signed normal Mac update
is installed and launched; main app, Agent and listener run from the installed
bundle. Installed executable SHA-256 is
`7cd998abd3b66b5f163086575a04ab96be70f416cfd0230e56c503385e9eca95`.
Pairing, existing entitlements/requirements/profile and the native host catalog
are preserved and checked; the previous complete bundle is retained for rollback.
The existing iPhone build is unchanged.

Private test/build/validation logs use prefix
`maccompanion-physical-failure-20261004-selection-diagnostic-`.
Installation receipt:
`/private/tmp/maccompanion-physical-failure-selection-diagnostic-1-mac-install-20261004.json`.
This is instrumentation of the failing lookup, not a functional reliability fix.

## Separate startup failure and IPv4 route repair

Two direct physical attempts through Mirroring fail during initial native video
startup at 11:52:26.796 and 11:56:50.280. Enrollment succeeds, then the phone
records `native.launch.failed-native-tls-code-2`. Neither attempt reaches a
surface switch. The refined Mac diagnostics do not report a selected-surface
rejection. These startup attempts are a separate failure from the earlier
`prepareReplacement` lookup rejection.

Source tracing identifies a concrete address-format defect. The primary route
reader returns `IPv4Address.debugDescription` directly. An interface-bound IPv4
address can include `%en0` in that debug string, whereas the native TLS boundary
accepts only numeric address text through `inet_pton`. A local probe using a
documentation address reproduces the rejection; a second probe reconstructs
the address from its exact `rawValue` and obtains accepted numeric IPv4 text.
The actual phone endpoint text is not logged, so this probe alone does not
establish that the defect caused the physical startup failure.

The normative managed-host document and its sole indexed launch fixture are
updated before the minimal repair: IPv4 is reconstructed from the measured
address bytes before conversion to text. IPv6 handling, selected-route bytes,
port authority, certificate validation and pairing remain unchanged. The two
focused route tests, 125 indexed fixtures, required full stable validation,
normal Mac build, device SDK inventory and normal iPhone build pass under
Xcode 27.0 (27A266a).

Matching normal updates with source SHA-256
`d372301bca022ac732ae02474cf4c5fb124969eee3af0c97b7fadb09b1e4c15c`
are signed and installed on the Mac and physical iPhone 18 Pro Max. Existing
pairing, Keychain group, signing metadata and native host catalog are preserved.
Mac executable SHA-256 is
`f40e8bd216ba13e3c604a5028804b50862e2c002b2e2a7f8aadb4701a2072665`;
signed iPhone executable SHA-256 is
`6bbe0f79af216b969137271adc2b1410bb896fbebc97b1e6b4fd179bdf79128b`.
The new main app and Agent run from the installed bundle and the Agent listens
on its existing port. Previous bundles and all attempt logs remain private.

Private evidence uses `maccompanion-physical-failure-20261004-` prefixes for
`ios-selection-diagnostic-repro-1.log`, `ios-selection-diagnostic-repro-2.log`,
`host-selection-diagnostic-repro-1.ndjson`, `scoped-route-probe-v2.log`,
`scoped-literal-probe.log`, `ipv4-route-regression.log` and
`ipv4-route-stable-validation.log`. Installation receipts are
`/private/tmp/maccompanion-physical-failure-ipv4-route-mac-install-20261004.json`
and `...physical-failure-20261004-ipv4-route-ios-install.json`.

After installation, Mirroring briefly reports that it disconnected because the
phone is in use, then reconnects. The matching updated phone retains its
authenticated pairing and starts normal Control at 12:18. Its journal records
`native.launch.route-bound`, verified server/app-list/launch responses, native
preparation, connected video, presentation and input admission. Video advances
from 12:18:28.969 through 12:22:08.819, approximately 220 seconds. The earlier
native TLS code-2 failure does not recur in this attempt. This verifies physical
startup after the minimal address repair; the prior unrecorded endpoint text
still prevents attributing its exact address annotation retrospectively.

Mirroring clicks do not activate the session toolbar or Close control during
this session. This observation is not attributed to a phone UI defect without
further proof. The native Mirroring Home control works; after backgrounding,
native input is fenced and the primary ends, and the foreground app returns to
an authenticated workspace. That journey is not counted as a passing Control
resume test. No switch is performed, so it cannot verify or disprove the original
selected-surface failure. A direct phone switching attempt is requested to
capture the refined check without those Mirroring interactions.

Startup and foreground observations are preserved privately as
`maccompanion-physical-failure-20261004-ipv4-startup-1.log`,
`...ipv4-startup-foreground-1.log` and
`...host-ipv4-startup-foreground-1.ndjson`. No unbounded log collector remains.

## Latest physical repeated-switch failure: native placement rejection

The user reports another failure after a few switches. The affected phone and
installed Mac still use the signed `d372301b...` candidate above. Private evidence
uses the same `maccompanion-physical-failure-20261004-` prefix with suffixes
`ipv4-switch-failure-2-ios.log`, `ipv4-switch-failure-2-ios-copy.json` and
`ipv4-switch-failure-2-host.ndjson`. Mac records are filtered by the installed
executable path; test processes are excluded.

At 13:40:15 the phone starts Control and admits input. Three retained switches
complete in 965, 846 and 2,595 ms. The fourth begins at 13:40:43.162. Enrollment
drains at 44.147, selection is submitted at 44.151, and the new bootstrap capture
starts at 44.548. The phone records host acknowledgement at 44.834, native
preparation at 45.461, and retention of the existing connection at 45.464. It
records an unexpected native disconnect at 45.508–45.509, before a new
presentation or input admission. The coordinator fails at 45.510; the switch
is cancelled after 2,377 ms.

The Mac runtime becomes inactive at 45.548. Its watchdog retires at 45.579 while
both the original permit and selected-capture predicate remain current. Closed
child diagnostics preserved on retirement at 45.633 report
`selected-capture-sample-rejected=7` and `selected-capture-stream-error=6` for a
window capture. The later unavailable backend and invalid input-read errors
follow teardown. The primary closes only at 13:40:59.245. No refined
selected-surface lookup rejection is recorded in this attempt.

Stage 7 is the exact aspect-fit content-placement check: at least one edge or
dimension differs from the expected centered rectangle by more than one encoded
pixel. The original adapter treats that first mismatch as terminal, stops the
native capture, and thereby disconnects the retained video connection before
new-frame readiness. This establishes the initiating check in this attempt.
Raw geometry is intentionally not recorded, so whether the rejected rectangle
was a delayed previous placement or another mismatch is not established.

## Reproduced repair and verification

A synthetic native test provides a valid-format, valid-time previous-placement
frame after successful filter/configuration updates. With the original adapter
it reproduces the same stage-7 and stream-error-6 termination. Its private log
is `...placement-before-repair.log`; the failed run is retained.

The normative continuity specification and sole indexed fixtures are updated
before the runtime repair. After both platform updates complete, the adapter
discards placement mismatches until the first strictly matching replacement
frame, for at most two seconds. Rejected samples are never tagged, delivered,
encoded, or used as presentation/input evidence. There is no added fixed wait:
a matching frame proceeds immediately after the existing timestamp cutover.
The first matching frame closes the interval; later geometry changes remain
terminal. Malformed samples, revoked original ownership, update failures and
other validation errors remain terminal. An owned, generation-fenced timer
also expires if no sample arrives; obsolete updates and Stop cannot reopen it.
Closed diagnostics distinguish a discarded previous placement from another
mismatch without recording geometry or content.

The repaired native script passes 19 lifecycle/sample, three indexed placement,
22 indexed continuity and four retained-capture cases, plus context, handoff,
actual H.264/HEVC depacketizer and selected bridge regressions. It covers timeout
without samples, revocation, malformed samples, post-admission geometry change,
Stop and obsolete-timer fencing. Required stable validation passes under
Xcode 27.0 (27A266a), with 125 indexed fixtures. Earlier restricted-cache and
display-mode failures are retained; the authorized reruns pass without weakening
checks. A cold host build fails to resolve its upstream download; the verified
warm source cache builds successfully, with the prior build products and
provenance preserved separately.

The rebuilt native capture source SHA-256 is
`c02df02746e0a9738593aee7de5ffb8e1c18a6e07cc12295f90304cda216da76`.
The fresh package verifies its complete file, source, dependency and supervisor
bindings. Its signed host preserves the existing bundle identity, designated
requirement and entitlements. Signed catalog SHA-256 is
`f05e3645cfd64fc25700165d7781cc0e27e1acaa41a4938214b3f666217018b3`;
the normal Debug Mac composition pins exactly those bytes. Final source SHA-256
after that catalog update is
`dfbc6d5f6b94ce5b5ad86d4678f4c332ad335376eb6c9989c0dd3829ee1a29c6`.
Final-source `bash scripts/validate.sh` and the normal Mac rebuild pass under
stable Xcode 27.0 (27A266a). The private final logs are
`...placement-final-stable-validation.log` and
`...placement-final-normal-mac-build.log`.

The first packaging attempt signs containing bundles but misses Xcode's emitted
Debug implementation libraries. Both app and Agent abort during dynamic loading
because those libraries retain ad hoc signatures with a different signing team.
Deep signature verification alone did not detect this launch incompatibility.
The failed candidate, launch reports and private startup log are preserved.
The corrected private staging step signs every normal-app Mach-O before its
containing bundle, verifies the existing signing team, and records all code
hashes. The exact already-signed native host catalog is preserved throughout.

The corrected signed normal Mac app is installed and launched. Executable
SHA-256 is
`b2fc6897bf2aceff16072aee76e97e4a65b374a4e7226f5f80c579d893de6fc0`;
Debug implementation library SHA-256 is
`4c443148740659f93e1f72eb0b607aee95c15eb99127b188e7615a56d1629f8b`.
The complete installed normal code graph, signed host catalog and final source
digest match the verified receipt. Main app and Agent run from the installed
bundle, and the Agent listens on the existing TLS port. Existing pairing,
entitlements, designated requirements and development profile are preserved.
The compatible physical iPhone client retains its `d372301b...` build; no phone
wire, crypto or client behavior changed in this repair. Complete prior Mac
bundles are retained for rollback.

Installation receipt:
`/private/tmp/maccompanion-physical-failure-placement-mac-install-v2-20261004.json`.
Runtime launch check:
`...physical-failure-20261004-placement-installed-processes-v2.json`.
The baseline phone journal still ends at the captured 13:40 failure. The user
is asked to repeat 10–20 direct physical switches with the newly installed host.
No physical repair pass is claimed until a new journal establishes it.

## Required next proof

Repeat the physical view-switch sequence on the installed update and correlate any
discarded-placement reason, new-frame/input admission or first rejecting check.
Do not count native synthetic regressions or the earlier Simulator campaign as
physical acceptance. The earlier input-posting and selected-surface lookup
failures remain open; production readiness and long-session acceptance remain
open.
