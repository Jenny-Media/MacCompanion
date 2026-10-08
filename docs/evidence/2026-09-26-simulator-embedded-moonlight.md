# Simulator playback through the extracted Moonlight engine

Date: 2026-09-26. This extends the [foundation checkpoint](2026-09-26-sunshine-moonlight-foundation.md).
It proves the experimental extracted component against the source-built Sunshine
host, not normal MacCompanion enrollment or approval.

## Configuration and repair

- Pinned Sunshine `v2026.914.233613`, commit `63d35f702ee9e362e43263742981836ec0710384`.
- Pinned Moonlight iOS 9.0.2, commit `85af0f75622bb2636481afda8b0fc5cc33d5956e`.
- Xcode 27.0 (`27A266a`), macOS 27.2 (`26B5091g`), dedicated iOS 27.0
  Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.
- `reference_build.py ios-embedded` embeds `CompanionMoonlightEngine`; an explicit
  launch environment flag selects it in the upstream reference controller.
  The original upstream pairing/launch provides connection credentials.
- Namespaced extracted Objective-C renderer and callback symbols permit coexistence
  with the reference client. No release target links the experimental component.
- Actual startup exposed missing `serverCodecModeSupport`: moonlight-common-c
  rejects zero before stage callbacks. The configuration now requires and forwards
  this server metadata. Earlier invalid-preflight results did not prove native
  network failure behavior. The revised tests exercise the real refusal path.

## Measured results

Two consecutive streams in the same reference app process (`43165`) produced
these fixed diagnostic events, in local time:

| Event | First stream | Fresh stream after drain |
| --- | --- | --- |
| Connection started | 17:08:45.464 | 17:09:39.618 |
| First decoded frame displayed | 17:08:45.730 | 17:09:39.868 |
| Reference controller requested Stop | 17:08:47.828 | 17:09:41.875 |
| Native Stop drained | 17:08:47.956 | 17:09:42.011 |

The explicit `MACCOMPANION_REFERENCE_AUTO_STOP=1` test seam invokes the existing
controller return-to-app-list path two seconds after video appears. The first
teardown was also visually checked at the app list. This is controller/lifecycle
evidence; attempted edge drags did not trigger Stop and gesture acceptance remains
unverified.

The final native XCTest result is **4 passed, 0 failed, 0 skipped**:
`/private/tmp/maccompanion-sunshine-moonlight-20260926/embedded-engine/DerivedData/Logs/Test/Test-CompanionMoonlightEngine-2026.09.26_17-07-23--0400.xcresult`.
`xcresulttool get test-results summary` confirmed that result. The actual test
execution took 10.598 seconds. A prior run's ten-second failure deadline was too
short for native RTSP retries; the revised failure-path deadline is twenty seconds.
An older failed run finished diagnostic collection later and appended to the
shared log, so the final result bundle is authoritative.

`reference_build.py verify` passed for pinned sources and patch hashes.
`bash scripts/validate.sh` completed with exit 0; repository validation is separate
from these live Simulator checks. No physical iPhone was used.

## Scope and cleanup

The owned host used loopback, finite lifetime, isolated private credentials, silent
audio, and disabled input. The installed Sunshine configuration was not used.
The reference Simulator app was stopped and the exact owned host supervisor was
terminated; its probe reported exit 143. Private state and raw logs remain outside
Git.

Normal MacCompanion Control composition, authenticated enrollment/approval bridge,
input and modifier-key acceptance, audio, sustained/reconnect network tests,
dependency/TCC admission, physical installation, and release gates remain open.
Observe, Act, and Control grants and normative authentication semantics are unchanged.
