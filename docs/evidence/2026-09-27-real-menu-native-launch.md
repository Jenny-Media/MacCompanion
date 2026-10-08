# Real menu admission and managed native Desktop launch

## What changed

The managed Sunshine probe now uses `InteractiveMenuRuntimeOwnerV0` for install,
media admission and surface acknowledgement. The backend no longer receives a
constructed acknowledged snapshot: it reads the production owner's atomic
current snapshot. An unacknowledged Desktop is rejected before host preparation.
Invalidating the actual menu runtime independently retires the managed host and
removes its private credentials while the primary attestation authority remains
otherwise current.

The native launch XML parser and encrypted-route validator are shared between the
iOS launch adapter and this Mac probe. The admitted in-memory TLS identity now
performs a real Sunshine `/launch` for the sole Desktop. The shared parser verifies
gamesession success and an exact `rtspenc` loopback address and port. Stream key
material is generated privately and cleared; it is never printed or committed.

## Evidence snapshot

Source input SHA-256:
`6a9bee20685294df51fb87e44becc4bcf6e8bce6eba6754e1a597fa6649ec9e2`.
Pinned Sunshine binary remains:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.
Stable Xcode 27.0 (27A266a), macOS 27.2.

- The managed host probe passes real menu admission, rejection before
  acknowledgement, certificate proof before registration, actual mTLS Desktop
  metadata/launch, encrypted stream route, sealed route/listener, port conflict,
  invalid DER/proof and menu Stop/credential-cleanup checks.
- Its report explicitly records productionMenuRuntimeAdmission,
  unacknowledgedDesktopDenied, menuStopRetiresHost, actualNativeHTTPSLaunch and
  encryptedStreamRouteVerified. It records decodedFrame,
  authenticatedLocalXPCFlow and authenticatedPrimaryFlow as false.
- Final stable `bash scripts/validate.sh` exits 0; `git diff --check` passes.
- Eight real TLS checks pass.
- Fifteen native Simulator checks pass on the dedicated MacCompanion Simulator,
  including the same launch XML/route parser used by the live host probe.
- Both unsigned SDK builds pass. All six framework inventory entries and live
  host/TLS reports match the source fingerprint above. Release admission remains
  false.

Reproduce with the existing `test_managed_host.py`, `test_native_tls.py`,
`engine_build.py` for both SDKs and `candidate_inventory.py`, using
`--root /private/tmp/maccompanion-sunshine-moonlight-20260926`. The Simulator test
UDID is `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.
Private report paths are the owned root's managed-host/TLS report JSON files,
embedded-engine provenance files and native-video-candidate-inventory.json.
Repository validation log: `/private/tmp/maccompanion-real-menu-validation.log`.

## Limits and next step

Indicator/capture/input platform effects and legacy bootstrap media are explicit
substitutes. The acknowledgement is a typed test bootstrap, not a decoded phone
frame or native presentation receipt. The local request bridge is still in-process,
and the primary authority remains injected. A successful launch returns an
encrypted stream route; this probe does not connect a decoder or prove playback.
It does not prove TCC attribution, normal automatic app composition, native input,
corresponding-source admission, signing, installation or physical acceptance.
The previous three normal Control journeys/five pairing regressions cover the
unchanged production Control sources, not native playback. The installed apps and
physical iPhone were untouched.

Next: exercise native enrollment through the actual authenticated local-XPC and
primary session with the normal client composition, then verify a stable frame,
Stop/reconnect and native presentation/input admission. Release gates remain open.
