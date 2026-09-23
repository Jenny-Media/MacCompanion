# WebRTC captured-stream feasibility checkpoint

Native WebRTC delivered an owned ScreenCaptureKit test window to an iPhone,
an iPad, and a dedicated iOS Simulator. The revised physical sessions passed
five-minute observations and continued advancing during a further four-minute
period without paired-device file transfers. The operator confirmed moving
video on both devices, including the revised iPhone receiver.

This supports continuing with WebRTC as the video foundation. It does not
approve production integration or establish reliable recovery on changing
networks. The initial iPhone stream froze, and its root cause remains open.

## Configuration and evidence

- WebRTC 153.0.0, pinned archive and digest from the existing disposable-probe
  admission; Swift 6, Xcode 27.0 (27A266a), SDK 27.
- ScreenCaptureKit selects only the capture app's exact synthetic window ID.
  H.264 sends 1280 x 720 video with a 30 fps ceiling; no audio or remote input.
- Final apps exclude VPN and cellular adapters using native WebRTC options.
  The selected local receiver candidates reported Wi-Fi on both physical
  devices. This does not test WAN, relays, Tailscale, or Wi-Fi roaming.
- iPhone 18 Pro Max on iOS 27.2 and iPad Pro 12.9-inch (3rd generation) on
  iPadOS 26.7. The operator explicitly authorized registering the iPhone for
  development testing. Signing values and profiles remain outside the repo.
- Offer/answer files move through existing paired-device tooling or local
  Simulator storage. No external signaling/ICE service or listener was added.
- Exact source hashes and compact results are in the adjacent
  [JSON record](2026-09-22-webrtc-streaming-probe.json). Raw filtered counters,
  build logs, and UI results are retained in the local evidence directory named
  there. Screenshots, SDP, device identifiers, and signing material are not
  included in the repository record.

## Checks completed

| Check | Result and limit |
|---|---|
| Mac capture, device receiver, Simulator receiver builds | Passed; final Mac sources match the capture/core files frozen for the final receiver build |
| Real capture startup | 10/10 fresh launches found the exact owned window and produced complete frames and an offer |
| Final LAN-only synthetic lifecycle | 10/10 connection, ICE restart, and Stop cycles passed; zero invalid, wrong-generation, or nonincreasing synthetic frames |
| Original default-adapter lifecycle | First batch passed nine cycles then timed out gathering ICE; separate retry passed 10/10 |
| Final physical observation | Both devices passed 300 seconds with a fresh matching final sample and advancing frames in the final ten seconds |
| Quiet observation | Both devices continued advancing across more than 240 seconds without paired-device file transfers |
| Final native Simulator UI | Rotation with continuing video, actual Stop button, and Home/reopen tests passed; Stop/background hide video, retire the current session, and restore normal idle behavior |
| Controlled source stall | Suspending only the test capture process for eight seconds blanked stale video; resuming restored current frames on the same session. This is not a network-outage test |
| Physical appearance | Operator confirmed moving video on both devices; initial iPad rotation and Home/reopen passed; final hands-on results are recorded separately in JSON |
| Existing repository tests | 1,837 Swift Testing tests across 42 runs passed in separately executed suites; relevant platform builds also passed |
| Required aggregate validator | Blocked by existing fixed references to the absent `/Applications/Xcode-beta.app` tool paths; independent remaining validators passed except the analogous notarytool-path check |

The original synthetic one-hour run passed after 3602.9 seconds. Its post-warmup median-window RSS change was -3.97 MiB, with fitted growth 0.386 MiB/minute. That run used the original default-adapter configuration. A separate 300.7-second synthetic run of the final LAN-only configuration passed; it does not satisfy a one-hour growth gate. Neither run is a physical-device memory or screen-to-screen latency measurement.

The capture pattern can be sampled twice by ScreenCaptureKit. Its
`nonIncreasingFrames` counter combines duplicate and backwards sequence values;
it is not an RTP reorder counter. Captured-stream acceptance therefore does
not assert zero reordered packets. Runtime statistics identify VideoToolbox
encoding with `powerEfficientEncoder: true`; receivers identify VideoToolbox
decoding but report `powerEfficientDecoder: false`. Hardware-efficient decoding
has not been established. Brief subsecond freezes remain in WebRTC statistics;
the successful five-minute runs are not a claim of perfectly smooth video.

## Failures retained and changes made

The first iPhone stream froze after appearing to connect. Diagnostics showed
capture and encoding continuing while received transport bytes and decoded
frames stopped. Adapter selection is a hypothesis, not a proven root cause.
The experiment now excludes VPN/cellular adapters, records selected-candidate
metadata without addresses, hides disconnected or stale video, and preserves
the ability to stop. Current-frame delivery can restore the display within a
still-active session; terminal failure requires a fresh session.

One intermediate observation incorrectly passed after the app backgrounded
because its connector discarded retired-session status and reused an old
sample. That result is explicitly invalidated in the retained audit. The final
connector keeps mismatched/retired status and requires a matching fresh final
sample plus recent frame progress. The final physical results use this stricter
check. The receiver now suppresses auto-lock only during a bounded active
session and restores normal idle behavior on Stop/background/expiry/failure.

Capture startup previously failed when the newly created window was absent
from an immediate enumeration. The revised bounded lookup includes offscreen
windows and retries only the exact owned window; it never broadens capture to
another window or an entire display.

## Next implementation gate

Keep the foundation reuse decision, but complete these bounded tasks before
replacing the production media path:

1. Run a short physical Wi-Fi interruption and reconnect check to target the
   observed freeze. Require visible loss state, bounded cleanup, fresh-session
   admission where necessary, and no stale-frame resurrection. The operator
   chose to skip the longer physical soak on September 22; long-session
   reliability remains unverified and does not block the next development step.
2. Measure physical screen-to-screen delay and frame pacing under an explicit
   workload; test source/resolution changes and device thermal/memory behavior.
   Synthetic timestamps are not visible latency, and host process RSS does not
   measure device or GPU allocations.
3. Design a narrow WebRTC video adapter: retain ScreenCaptureKit source
   selection, native rendering, and MacCompanion's independent grants and
   existing input path. Reuse WebRTC encoding/transport/decoding and statistics.
   Bind signaling and peer identity to the authenticated session and Control
   generation; first update the normative specification and golden fixtures.
   File exchange in this probe must never become production authorization.
4. Complete binary provenance, transitive notices, dependency-policy, privacy,
   signing, and supported-OS review before admitting WebRTC to release targets.
   Resolve the fixed Xcode-tool path validation issue as a separate reviewed
   change, then require the full validator to pass.

Production targets, pairing, grants, input routing, permanent identities, and
release dependencies are unchanged. Sunshine/RustDesk comparison work remains
paused. Reproduction steps are in the
[experiment README](../../Experiments/WebRTCProbe/README.md).
