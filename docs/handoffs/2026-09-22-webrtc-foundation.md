# WebRTC foundation handoff — September 22, 2026

Follow-on authenticated signaling work is recorded in
[`2026-09-22-webrtc-authenticated-signaling.md`](../evidence/2026-09-22-webrtc-authenticated-signaling.md).

## Decision and scope

Continue evaluating native WebRTC as MacCompanion's video foundation instead of
rebuilding encoding, transport, decoding, and media statistics. The experiment
has demonstrated actual Mac-to-iPhone/iPad video. It is not a production
integration, dependency admission, or release-readiness claim.

The user prioritized reuse, requested automatic background-to-foreground
recovery, and explicitly skipped a longer physical soak. Keep that decision:
long-session physical reliability remains unknown, but another soak is not a
prerequisite for the next development step. Sunshine/RustDesk comparison work
remains paused.

This checkpoint includes the disposable probe, native test apps, lifecycle
tests, bounded file relay, experiment dependency-policy exception, and evidence.
Production targets, pairing, independent Observe/Act/Control grants, input,
permanent identities, and release dependencies are unchanged.

## Current implementation

| Area | Entry point and behavior |
|---|---|
| Reproduction | [Experiment README](../../Experiments/WebRTCProbe/README.md); pinned `stasel/WebRTC` 153.0.0 archive, SHA-256 checked before extraction |
| Build generation | `build.py`, `streaming_build.py`, and `apps_build.py` in the experiment; frozen sources and generated projects stay in temporary directories |
| Media | `MediaPeer.swift` and `SyntheticFrames.swift`; H.264, 1280 x 720, 30 fps ceiling, native WebRTC transport and statistics |
| Mac capture | `CaptureApp.swift`; ScreenCaptureKit captures only the exact owned synthetic window, with no display fallback |
| iOS presentation | `ReceiverApp.swift`; aspect-fit native rendering, bounded latest-frame handoff, session guards, visible Stop |
| Test signaling | `Exchange.swift` and `connect.py`; local/paired-device files, original expiry and generation, fresh peer/session per foreground recovery, correlated requests/offers/answers |
| Regression checks | `ReceiverUITests.swift`; eight foreground cycles, interruptions during reconnect, advancing frames, Stop persistence, and separate expiry check |

The receiver closes its old peer and clears video on background. Foreground
return requests a fresh peer within the original test expiry. Negotiation or
terminal peer failure preserves resume intent and permits three automatic
retries with 1/2/4-second backoff while active. A later foreground return can
retry again within the same expiry. Explicit Stop and expiry cancel automatic
work. Process eviction and device reboot recovery are not implemented.

Only current frames produce Receiving. A 1.5-second absence of fresh presented
frames, checked every 0.5 seconds, hides old video and shows Waiting for video.
This does not itself declare a Wi-Fi outage or close a still-connected peer.
LAN-only factory options exclude VPN and cellular adapters. There is no audio,
remote input, external ICE server, or network signaling listener in this probe.

## Evidence to carry forward

Read the [responsiveness checkpoint](../evidence/2026-09-22-webrtc-responsiveness.md)
and its adjacent JSON first. Earlier checkpoints are historical, not the status
of the latest receiver:

| Evidence | Result and boundary |
|---|---|
| Latest builds | Simulator and signed device receiver passed; installed on iPhone 18 Pro Max. Reused Mac app has matching capture/core source hashes. The iPad has an earlier test build |
| Latest Simulator | Eight foreground cycles passed, including an injected negotiation failure and automatic retry; Stop persistence and separate 30-second expiry regression passed |
| Latest stall check | A four-second capture-process pause hid video after 1.65 seconds; recovery followed about 0.11 seconds after resume on the same session. This is not a Wi-Fi or glass-latency measurement |
| Latest physical regression | First attempt could not initialize UI automation. Retry failed its 40-second Receiving wait during one cycle; eventual recovery was recorded. Do not report a physical regression pass |
| Physical timing observations | Eight foreground recoveries took about 2.7–3.7 seconds; one took 61.1 seconds. Partial runs are included; this is not a controlled benchmark |
| Operator acceptance before latest change | User confirmed both Wi-Fi and foreground recovery worked; Wi-Fi recovery felt fast, loss indication and foreground recovery felt slow. No corresponding exact manual timing trace is available |
| Earlier retry build | Eight physical iPhone foreground cycles passed on its repeat run. See [retry checkpoint](../evidence/2026-09-22-webrtc-reconnect-retry.md); do not transfer that pass to the latest build |
| Earlier capture baseline | iPhone and iPad each passed five minutes, plus four minutes without file transfers; operator confirmed moving video and rotation. See [streaming checkpoint](../evidence/2026-09-22-webrtc-streaming-probe.md) |
| Earlier synthetic baseline | One hour passed using default adapter selection; a separate LAN-only run passed five minutes. Neither proves latest physical or GPU-memory reliability |
| Repository validation | `bash scripts/validate.sh` stops at the existing absent fixed Xcode-beta stapler path. Earlier separately run 1,837 Swift tests are historical; no current aggregate pass is claimed |

The slow physical cycle had four consecutive 15-second device-file copy
timeouts. About 59.6 seconds elapsed before the replacement offer was admitted,
then about 1.5 seconds to Receiving. The file tool's underlying failure is
unresolved. Media settings should not be tuned based on this signaling delay.

The initial iPhone freeze also has no proven root cause. LAN-only selection and
later successful observations are evidence of improvement, not proof of its
cause. Likewise, the earlier spontaneous stopped report must not be attributed
to a deliberate user Stop; the older log did not identify its trigger.

## Next bounded work

1. Design the integration boundary first. Inspect the existing
   [primary-session composition](../../spec/capability-protocol/v0/primary-session-composition.md),
   [Control security profile](../../spec/interactive-control/v0/security-profile.md),
   [session/channel messages](../../spec/interactive-control/v0/session-channel-messages.md),
   and [media contract](../../spec/interactive-control/v0/media-records.md).
   Map offer/answer/ICE and peer identity onto existing authenticated session
   ownership. Do not assume that the current channel already accepts WebRTC
   messages or that experimental resume intent constitutes Control authority.
2. Write the narrow contract and authoritative fixtures before changing wire or
   security behavior. Use `spec/fixtures/manifest.json`, not a second fixture
   corpus. Cover identity/fingerprint binding, session and Control generation,
   expiry/revocation, duplicate/stale messages, background return, Stop racing
   with negotiation, and old-peer callbacks. Reconnection must not extend or
   resurrect revoked authorization.
3. Implement a small media adapter behind the reviewed boundary. Starting code
   includes `ClientInteractivePrimaryChannelV0`, `InteractiveHostPrimaryAdapterV0`,
   and `ClientMediaStreamAuthorityV0`. Reuse WebRTC for media; retain native source
   selection/rendering and existing input/grant ownership. Keep the experiment
   as a comparison until the replacement path has evidence. Do not grow the
   paired-device file relay into a bespoke network signaling service.
4. Run short, targeted native/device tests through that signaling path: repeated
   foreground recovery, Wi-Fi interruption/restoration, advancing current
   frames, Stop, expiry/revocation, and stale callback rejection. Measure time
   to offer admission and first presented frame separately. Keep failures and
   manual appearance acceptance distinct from counter-based checks. Do not add
   the skipped long physical soak implicitly.
5. Before release-target admission, finish binary provenance/reproducibility,
   transitive notices, supported-OS, dependency-policy, privacy, and signing
   review. Resolve fixed Xcode-tool validation paths separately without weakening
   the validator; then obtain an aggregate pass. No release admission occurred
   in this checkpoint.

## Resume locally

The relevant repository is `/Users/yihong/work/MacCompanion`, even if the task's
working directory opens in MacTools. Use MacCompanion's `AGENTS.md`.

- Last toolchain used: `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0
  (27A266a). Set `DEVELOPER_DIR` per command; do not globally switch Xcode.
- Test identities: `dev.maccompanion.webrtc.capture` and
  `dev.maccompanion.webrtc.receiver`; generated apps target OS 26.0 or later.
- Physical devices previously used: iPhone 18 Pro Max and iPad Pro 12.9-inch
  (3rd generation). The iPhone was explicitly authorized and registered for
  development testing. Rediscover current connections; do not assume availability.
- Dedicated Simulator name: MacCompanion WebRTC QA. Reuse only that test
  Simulator; rediscover its identifier instead of touching unrelated devices.
- At handoff, bounded test relays/capture sessions have ended. Installed apps
  alone cannot resume them. Start a new host lease and matching relay if another
  experiment run is needed. Screen Recording and Local Network were granted
  previously; recheck after rebuilding/reinstalling rather than resetting TCC.
- Local evidence root:
  `/Users/yihong/.codex/visualizations/2026/09/12/01a093de-bea3-7922-bc20-22ff9e60c81e/streaming-research/run-2026-09-22`.
  `responsiveness/` contains the latest frozen sources, build logs, counters,
  timing records, and native result bundles. `reconnect-retry/` and the older
  checkpoint JSONs locate earlier results.
- The verified archive is under the sibling
  `streaming-research/package-inspection/WebRTC-M153.xcframework.zip`.
  Recheck its digest with the builder; it is not committed.
- Latest generated receiver project: `/private/tmp/maccompanion-webrtc-apps-m33u44s0`.
  Reused signed Mac app: `/private/tmp/maccompanion-webrtc-apps-nt630wzx/MacData/Build/Products/Debug/WebRTCCaptureTest.app`.
  These are disposable local conveniences, not portable dependencies; regenerate
  from committed sources when absent. Use matching receiver and relay versions.

Certificates, profiles, device identifiers, SDP, screenshots, and raw result
bundles remain outside the repository. Source hashes in each JSON checkpoint
identify the exact tested version; do not collapse earlier passes and later
failures into one acceptance claim.
