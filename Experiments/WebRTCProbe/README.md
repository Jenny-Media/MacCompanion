# Disposable WebRTC streaming experiment

Start with the [current handoff](../../docs/handoffs/2026-09-22-webrtc-foundation.md)
for the latest results, open failures, and next integration step. Earlier
checkpoint documents retain their original test scope.

This experiment evaluates a pinned native WebRTC framework without changing
MacCompanion's production targets, pairing, grants, or input path. It has three
separate layers of evidence:

1. `build.py`: Swift 6 package/API/linkage checks on Mac, iOS, and Simulator.
2. `streaming_build.py` and `soak.py`: synthetic H.264 encoding, peer transport,
   decoding, numbered-frame checks, ICE restart, Stop, and process memory.
3. `apps_build.py` and `connect.py`: an actual ScreenCaptureKit capture of an
   owned synthetic window, displayed by a native iOS receiver. App lifecycle
   tests and physical operator observations are separate from local transport.

Use the inspected `stasel/WebRTC` 153.0.0 archive. Builders verify SHA-256
`3e3a8946f27510133e3feed04d05fa23505bbe366e977620503bfc7986c2b78f`
before extraction. Frameworks and generated projects stay outside the repo.
The [dependency admission](../../spec/dependency-policy/v0/profile.md) remains
limited to this disposable experiment. No external ICE or signaling server is
used. Test offer/answer files are exchanged through local Simulator storage or
Apple's paired-device file service; this is not production authentication.

## Build and synthetic checks

Select the installed full Xcode, then provide the previously inspected archive:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
webrtc_archive=/absolute/path/to/WebRTC-M153.xcframework.zip
python3 Experiments/WebRTCProbe/build.py --archive "$webrtc_archive" --run-mac
python3 Experiments/WebRTCProbe/streaming_build.py --archive "$webrtc_archive"
```

The streaming builder prints a new temporary build directory and saves frozen
source files, source hashes, and its compiler log. With that executable:

```sh
/private/tmp/maccompanion-webrtc-stream-<build>/round-trip \
  --seconds 6 --cycles 10 --ice-restart --lan-only
python3 Experiments/WebRTCProbe/soak.py \
  --executable /private/tmp/maccompanion-webrtc-stream-<build>/round-trip \
  --seconds 3600 --lan-only --output-dir /absolute/durable/path/new-soak-run
```

`--lan-only` excludes VPN and cellular adapters through native WebRTC factory
options, matching the capture and receiver apps. Omitting it retains WebRTC's
default adapter selection for comparison; record which configuration ran.

The output directory must be new. Preserve `events.jsonl`, `resources.json`,
`result.json`, and the source hashes together. After a ten-minute warmup, the
one-hour check requires median-window RSS growth at most 32 MiB and fitted
growth at most 1 MiB/minute. An interrupted or shortened test cannot meet that
gate. Internal timestamps measure the synthetic pipeline, not screen-to-screen
latency. Run failures remain evidence even when a subsequent attempt passes.

The synthetic executable needs ordinary macOS access for IOSurface allocation
and peer sockets. An execution sandbox can reject this independently of Screen
Recording consent. It captures no screen content.

## Native capture and receiver

```sh
python3 Experiments/WebRTCProbe/apps_build.py \
  --archive "$webrtc_archive" --with-ui-tests
```

This prints a generated `WebRTCExperiments.xcodeproj`. Its app schemes are
`WebRTCCaptureTest` and `WebRTCReceiverTest`; both target OS 26.0 or newer. Build
the Mac app with an available Apple Development identity and manual signing.
Build the receiver for Simulator without signing, or for a physical device with
the existing development team/profile. Keep all signing values and profiles
outside the repository. Registering another device or updating Apple account
provisioning requires the operator's authorization.

Install and open the receiver on a dedicated Simulator or a paired device.
Launch the Mac app with a new session directory and a fresh generation:

```sh
webrtc_session=$(mktemp -d /private/tmp/maccompanion-webrtc-session-XXXXXX)
open -n /absolute/path/WebRTCCaptureTest.app --args \
  --work-dir "$webrtc_session" --seconds 600 --generation 81
```

For actual capture, enable **Screen & System Audio Recording** for the capture
app in System Settings, then relaunch with the same arguments or a new session.
The filter selects only this process's exact synthetic window ID. It never
falls back to another window or a display. Enumeration includes offscreen
windows so another Space cannot accidentally hide the owned target, and it
retries briefly while WindowServer publishes a newly created window. The app
captures neither audio nor user input. `--synthetic` bypasses ScreenCaptureKit
and must not be counted as capture evidence.

Connect to the receiver using one of:

```sh
python3 Experiments/WebRTCProbe/connect.py \
  --host-session "$webrtc_session" --simulator <simulator-id> \
  --output-dir /absolute/durable/path/new-simulator-run --observe-seconds 30 --maintain-seconds 600
python3 Experiments/WebRTCProbe/connect.py \
  --host-session "$webrtc_session" --device <paired-device-id> \
  --output-dir /absolute/durable/path/new-device-run --observe-seconds 30 --maintain-seconds 600
```

Allow Local Network access on the physical device if prompted. The connector
checks session identity, expiry, fresh diagnostics, valid frame advancement in
the final ten seconds, wrong-generation markers, and visible video state.
Retired or mismatched sessions are retained as evidence and cannot produce a
pass from an older sample. It leaves the apps running for interaction
tests until Stop or the bounded session expiry. It does not grant permissions,
install apps, update provisioning, or bypass device lock. The durable output
contains counters and filtered media statistics; SDP stays in temporary test
storage. Do not commit SDP, screen images, certificates, or provisioning files.

The receiver keeps the device awake only during a bounded active session.
Backgrounding closes the old peer, clears the video, and restores normal idle
behavior. Returning to the foreground requests a fresh peer through the same
local or paired-device relay, provided the original test lifetime has not
expired. Keep `connect.py --maintain-seconds` running for this disposable
reconnection setup. Stop and expiry cancel pending resume; reopening after
Stop does not reconnect. Negotiation failure, terminal peer failure, and a missing first frame trigger
up to three automatic retries with bounded backoff while the app is active.
Failure does not cancel the original resume intent. After the retry budget is
used, returning to the app can retry again within the unchanged test expiry.
Only current video frames produce the Receiving state. A disconnected peer or a 1.5-second absence
of fresh frames (checked every 0.5 seconds) blanks the old video; current frames can restore presentation
while the same session remains active. This is experiment behavior, not an
implementation of production authorization. The new peer has a fresh session
ID, while the exact owned source and original expiry remain unchanged. A
request ID binds the replacement offer/answer to the pending resume; stale
requests and offers after Stop cannot revive the receiver. This file channel
is temporary test orchestration, not a production signaling service. The relay
reads resume intent together with the receiver status in one bounded snapshot
and briefly waits for the local replacement offer before another device read.
Use the matching receiver and relay versions. Device-file transport overhead
is part of this test setup, not a measurement of production signaling latency.

The captured pattern can be sampled more than once by ScreenCaptureKit.
`nonIncreasingFrames` currently combines repeated pattern sequence numbers
with backwards sequences; it is not proof of reordered WebRTC packets. Keep
this counter visible, and do not claim a no-reordering capture pass from it.
The synthetic direct-source test separately requires zero nonincreasing frames.

## UI and physical lifecycle checks

Each native UI test requires a fresh connected captured session. Run the methods
separately, reconnecting between them:

```sh
xcodebuild -project /absolute/path/WebRTCExperiments.xcodeproj \
  -scheme WebRTCReceiverTest -destination 'platform=iOS Simulator,id=<id>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:WebRTCReceiverUITests/ReceiverUITests/testRotationAndStop test
xcodebuild -project /absolute/path/WebRTCExperiments.xcodeproj \
  -scheme WebRTCReceiverTest -destination 'platform=iOS Simulator,id=<id>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:WebRTCReceiverUITests/ReceiverUITests/testBackgroundAutomaticallyReconnects test
```

The first test checks portrait/landscape layout, continuing frames, the actual
Stop button, and a stable decoded-frame count afterward. The second checks eight Home/reopen cycles, including interrupted reconnects,
each with a fresh session and
advancing frames, then proves that explicit Stop stays stopped after reopening. Save the
corresponding receiver status to confirm background/Stop video clearing and
normal idle behavior, as well as fresh session IDs after resuming. A separate
`testExpiredBackgroundSessionDoesNotReconnect` must be started immediately
after connecting a 30-second host session; it waits past expiry in background
and verifies that returning cannot reconnect. Test screenshots and `.xcresult`
bundles stay in local evidence storage.

On each physical device, confirm moving video and proportional rotation, then
Home/reopen with automatic reconnection and visible Stop on a fresh session. Device counters alone
do not establish on-screen appearance or touch behavior. This receiver has no
remote-input implementation, and the probe does not yet prove terminal network
loss handling, source/resolution changes, production revocation, or visible
latency. Hardware-backed encoding requires runtime codec evidence; decoder
implementation names alone do not establish hardware efficiency.

The [package checkpoint](../../docs/evidence/2026-09-12-webrtc-package-probe.md)
and the [streaming checkpoint](../../docs/evidence/2026-09-22-webrtc-streaming-probe.md)
have distinct scopes. A working
disposable stream is feasibility evidence, not production integration approval.

The operator chose to skip a longer physical soak on September 22. Long-session
reliability remains unverified; it is not a gate for the next development step.
The earlier one-hour synthetic baseline remains historical evidence.

For deterministic failure recovery, launch the disposable receiver with
`--fail-reconnect-once` before the UI test. The first replacement negotiation
then fails deliberately; verify `automaticRetryCount` increases and later
frames resume. This injects a negotiation failure, not a Wi-Fi outage. A bounded
transition log and `userStopCount` distinguish a Stop-control callback from
network/negotiation failure without recording screen or input content.
