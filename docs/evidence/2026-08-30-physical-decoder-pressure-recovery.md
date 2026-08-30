# Physical decoder-pressure recovery

Date: 2026-08-30

## Observed failure

With the signed `9223daa` candidate installed on both the physical iPhone and
iPad, the clients could alternate rapidly between Ready and Reconnect. A
foreground `devicectl` console attached to the iPhone preserved its pairing and
exposed the first client-side failure:

```text
[MacCompanion live-control] media consumer rejected type=videoAccessUnit sequence=63 error=decodeSubmissionFailed
[MacCompanion live-control] media pump failed error=consumerRejected
```

The client then cancelled its primary connection. The Agent's later
`interactive role pair ended reason=invalidInputRead` and primary
`remoteClosed` messages were teardown fallout, not the initiating fault. Agent
logs also confirmed that the earlier singleton-primary replacement loop did not
recur with this candidate.

The historical decoder error did not retain its VideoToolbox status, so the
exact status for that frame cannot be recovered. Physical verification of the
superseding build therefore remains required.

## Repair

- Decoder submission failures now retain their exact `OSStatus` for future
  diagnosis.
- `kVTVideoDecoderNotAvailableNowErr` is treated as temporary real-time
  pressure: that output is dropped and a later authenticated frame can replace
  it without terminating Control.
- A successful asynchronous callback carrying `frameDropped` is likewise a
  nonterminal dropped output.
- Invalid sessions, malformed video and every other status remain terminal.
- The UIKit render coordinator ignores only the explicit dropped result.
- `_1xRealTimePlayback` was tested and rejected. Media timestamps are authored
  from the Mac's uptime and are ordering values, not the iOS playback clock;
  comparing unrelated device uptimes caused otherwise valid Simulator frames
  to be dropped.

Two focused tests freeze the narrow disposition policy. The integrated
real-window harness now also verifies the current Smart Zoom contract: ordinary
focus changes zoom the existing client surface locally and do not request a
new host capture surface.

## Automated verification

- `VideoToolboxClientDecoderV0Tests`: passed, covering accepted, temporary,
  invalid-session and malformed-data statuses.
- Real-Mac-window Simulator integration: passed all three integrated scenarios
  plus pairing regressions. Evidence root:
  `/private/tmp/maccompanion-feature-tests.1SgeaX`; its `report.json` is
  `passed`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash
  scripts/validate.sh`: passed on the complete source tree with exit status 0,
  including repository policy checks, every Swift package test catalog and all
  permanent-target builds.

## Remaining physical boundary

This checkpoint does not claim the reconnect loop is physically resolved. A
new exact signed iOS build must be installed on both devices, both clients must
remain independently connected, and dramatic content changes must no longer
cause decoder rejection or cross-device session replacement. Any recurring
terminal failure must be diagnosed using the newly retained `OSStatus` rather
than broadening the recoverable-status set without evidence.
