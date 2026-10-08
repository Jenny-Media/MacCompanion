# Native enrollment ownership, usability, and source preparation

Date: 2026-10-01. This follows the [installed enrollment and route repair](2026-10-01-installed-native-enrollment-and-route-repair.md).

## Changes and reproduced defect

The normal iOS App/Window picker now searches the privacy-limited application
names and window ordinals. Desktop remains available while searching. Successful
surface replacement no longer projects the terminal restart message during its
intentional drain. The normal-app UI journey searches for its disposable target
and checks that replacement did not display that message.

Investigation of an intermittent replacement failure found a separate client
ownership defect. The deterministic channel regression deliberately holds a
certificate validator that ignores cancellation. Closing the old enrollment
cancels its primary reservation, then waits for the validator. A fresh reservation
can begin before the old validator returns. Previously, the old close's second
unscoped cancellation retired the fresh reservation. The regression failed with
`Retired enrollment compensation canceled the replacement's exact fence`.

The specification and authoritative native-client fixture were updated before
the implementation. Each local enrollment owner now retains an opaque local
identity; both cancellation attempts may retire only its reservation. Joining
a completed primary cancellation clears the matching cancellation slot before
returning. The identity does not change the wire format, signatures, or grants.
The regression now passes with the existing 18 approval/ordering cases.

Native presentation diagnostics distinguish the closed primary error cases
without recording payloads, certificates, input, or arbitrary error descriptions.
The portable host probe now binds the selected verified package binary rather
than requiring an unrelated historical reference executable. Source snapshots
also retain the normal-app QA authoring inputs.

## Current candidate and validation

- Native first-party input fingerprint:
  `5f6aa030c2f59b83e4cdae7bcfe8a903d4c2b3b23d4d024fc68585676e543190`.
- Both normal native client SDKs rebuilt; the six-framework inventory verifies.
- The normal iPhone build uses production client adapters and contains no
  reference probe. Its signed executable hash is
  `8e2e0f783aba978e552b55e765f86ccf5ca771b04f0053801c4fae51e514b918`.
- Strict signature verification and installation on iPhone 17 Pro Max pass.
  The existing pair authenticates after installation.
- Full `bash scripts/validate.sh` passes on stable Xcode 27.0, with 118
  manifest-indexed fixtures. SwiftPM sandbox disabling is an execution setting;
  it does not substitute security or consent behavior.

### Repeated normal-app sessions

The first ten-session run failed after several successful presentations. Its
signed menu reported `signed-simulator-media-drain-failed-replyTimedOut` and
`local-xpc-invalidated`; the test status connection subsequently closed. Source
rebuilds were running concurrently. Workload correlation does not establish
the cause, and the ownership regression above does not prove this separate
media acknowledgement stall was repaired.

A second run, after compilation completed, passes ten native presentations and
ten start/Stop cycles. Keyboard, pointer, modifiers/shortcuts, between-session
Observe reads, saved workspace reopening, exact-key deletion, host retirement,
and restoration of the original Simulator app/data pass. The tested normal
Simulator executable hash is
`f2a1b1abee9c099a24cfd0ba08bb934d77e84cfd633f4f6b3c963a4b504ee504`.
Its native host package manifest hash is
`b270817ed33375ca3ce2a1458bfab11e41da4d77a137b46536b3a2f1df509daa`.

These are normal-client Simulator results against a disposable signed Agent and
menu. Human Mac consent is substituted and final input effects are synthetic.
They do not establish physical pointer, text, scroll, or selected App/Window
acceptance. The initial failed run remains a release reliability issue.

### App and Window replacement against the archive-built host

The normal app's App-selection journey passes against the portable host rebuilt
from the frozen archive. It verifies the real target catalog and search,
selected App capture, fresh native presentation, absence of false restart
guidance, keyboard/pointer/modifier/shortcut delivery, Stop, and a third native
presentation in a new Control session. The UI test takes 90.770 seconds; its
exact-key cleanup test, host retirement and original Simulator app/data
restoration pass. The normal Simulator executable is the same hash recorded
above; the host manifest is the archive package hash recorded below. Final
input effects and human Mac consent retain the Simulator substitutions.

The separate Window-selection journey also passes: the searched real Window,
fresh native replacement, input delivery, Stop and a new Control session produce
three presentations. Its UI test takes 90.525 seconds. Exact-key cleanup,
host retirement and original Simulator restoration pass against the same
normal-client executable and archive host manifest.

### Background and primary connection recovery

The separate normal-app recovery journey passes against the same archive host.
It verifies real iOS background input fencing, visible explicit-restart guidance
after foreground return, three fresh native presentations, host-induced primary
listener loss, Reconnect with the saved pair, and input/Stop/Observe delivery.
The UI and exact-key cleanup tests pass; host retirement and original Simulator
app/data restoration pass. This proves the disposable primary-cut recovery path;
it does not replace physical Wi-Fi interruption or Mac sleep/wake acceptance.

## Frozen source reconstruction

The new source archive contains 18 pinned upstream components, first-party
source, patch/build inputs, notices, codec sources, and normal-app QA source.
Private keys, profiles, screenshots, real audit stores, and device input are
excluded. Its archive hash is
`be1765c2de98db3a8503e8263bf3087d0ed0391e9e9be7ba4d26ab83ecd0499b`;
the source manifest hash is
`7077f18474fe959c54cee800bd28a6df7fa96a6e0cae379451f2c0c374925206`.

All 24 retained license/notice records, including the embedded TPCircularBuffer
notice, match the frozen manifest across all 18 components. This inventory keeps
legal compatibility approval unset.

The following reconstruction checks pass against that frozen archive:

| Component | Verified result |
| --- | --- |
| Runtime and SDK dependencies | Source-built Mac OpenSSL, miniupnpc, Opus and ICU; OpenSSL for both iOS SDKs |
| Codecs | Seven installed static libraries, including FFmpeg, SVT-AV1, x264 and x265; deployment inspection |
| Web UI | 193 integrity-checked package archives; offline dependency installation and build |
| Sunshine host | Rebuilt from extracted source and the verified dependency/codec/Web records; bound final link inputs |
| iOS native client | Both SDKs rebuilt from the extracted first-party and upstream source; six frameworks; Simulator component tests |
| Portable host | Rebuilt host, runtime libraries, OpenSSL CLI and first-party supervisor; closed dependency graph and signatures |

The rebuilt host executable hash is
`5c955705be2724114521fc96bbf9ce0e74ba6cd9bf28542f42294885194f2615`.
The archive package manifest hash is
`c8ccd31d3cc77683de1a97a38cf45ac6f01c8ac3f5afe4bba6b44c5e73f18ff5`.
Reconstruction does not claim identical binary reproduction, current normal
candidate admission for the historical archive adapter, complete corresponding
source delivery, or distribution approval. The reports retain
`correspondingSourceComplete: false` and `releaseAdmitted: false`.

## Physical and distribution work remaining

The new iPhone app reconnects with its saved pair. Attempts to start the next
physical input check stop at device approval; no approval-key presence is
substituted. Physical App/Window focus, pointer, scrolling, typing and modifier
acceptance still require a live approved session. Physical Wi-Fi interruption,
sleep/wake, and the longer current-candidate session remain unverified.

The installed Mac keeps the previously verified development host/catalog and
its pairing/TCC state. The newly reconstructed package is a separate artifact;
its different catalog is not silently installed under the old admission hash.

Production readiness remains open:

1. Resolve the media acknowledgement stall under concurrent workload.
2. Finish the physical checks for this exact candidate.
3. Admit native streaming into the actual Release composition. The normal native
   selection is still Debug-only; removing that guard does not establish the
   required exact package/source/process admission.
4. Verify matching distribution provisioning and the explicit Agent Keychain
   profile. Signing identities exist; matching cached MacCompanion distribution
   profiles were not found during preflight.
5. Complete corresponding-source/notice delivery and distribution review for
   the exact final artifacts. The owner's GPL decision is already recorded.
6. Build the distribution archives, signed-code/SBOM evidence, notarized/stapled
   Mac artifacts, and tested update/rollback package in the release environment.
7. Complete the [physical acceptance checklist](../physical-acceptance-checklist.md),
   including clean standard-user installation and the exact-source seven-date
   soak spanning at least 518,400 actual seconds. Historical campaigns do not
   supply elapsed time for this candidate.

No Developer ID/notarized native release, TestFlight upload, or public
publication is claimed.

## Private evidence locations

- Ownership failure and repair:
  `/private/tmp/maccompanion-native-owner-retirement-repro-v3-20261001.log` and
  `/private/tmp/maccompanion-native-owner-retirement-fixed-20261001.log`.
- Full stable validation:
  `/private/tmp/maccompanion-native-owner-fixed-stable-validation-20261001.log`.
- Failed repeated run:
  `/private/tmp/maccompanion-native-owner-fixed-ten-sessions-20261001/report.json`.
- Passing repeated run:
  `/private/tmp/maccompanion-native-owner-fixed-ten-sessions-20261001-v2/report.json`.
- Passing App replacement against the archive host:
  `/private/tmp/maccompanion-native-owner-fixed-app-replacement-20261001/report.json`.
- Passing Window replacement against the archive host:
  `/private/tmp/maccompanion-native-owner-fixed-window-replacement-20261001/report.json`.
- Passing background and primary-cut recovery:
  `/private/tmp/maccompanion-native-owner-fixed-recovery-20261001/report.json`.
- Installed phone build:
  `/private/tmp/maccompanion-normal-iphone17-owner-fixed-20261001/build-report.json`.
- Frozen source and rebuild records:
  `/private/tmp/maccompanion-release-readiness-20261001-v2/native-source-build-index.json`.

Private reports and test outputs remain outside Git. This document contains
only code/result descriptions, content-free failure codes, artifact hashes, and
evidence paths.
