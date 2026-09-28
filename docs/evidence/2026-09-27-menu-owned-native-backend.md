# Menu-owned native host backend checkpoint

## Scope and implementation

The normal Agent runtime route now constructs an inert native enrollment proxy
using the existing authenticated local menu connection. New prepare, activate,
health and retire records use the same bounded canonical codec, method admission,
generation/endpoint token, serialized sending, timeout and invalidation path.
The normative contract and manifest-indexed fixture precede the implementation.
The Agent retains the existing golden-vector proof verifier and durable grant/key
join; no additional pairing or approval semantics are introduced.

The Mac menu adapter owns the backend lifecycle. It joins the immutable public
scope to the acknowledged Desktop snapshot, resolves the opaque display locally,
and gives the injected factory only a physical display ID and a revocable permit.
Preparation reserves its slot before suspending. Stop joins late factory results,
pending preparation/startup and owned host retirement. A 50 ms watcher rechecks
current runtime/display. Stale retirement cannot stop a newer instance. Local
Stop, Agent loss and expiry close admission before cleanup awaits; an exact new
install can reopen it without overriding a later Stop.

Normal Mac composition accepts a native host factory. The default factory remains
absent pending dependency/process/TCC admission. The actual Sunshine adapter stays
under Experiments and is not linked into permanent release targets. Observe, Act
and Control retain their independent grants. Native input remains disabled.

## Verification snapshot

Stable toolchain: Xcode 27.0 (27A266a), macOS 27.2. Source input fingerprint:
`e08776aecb2319b464f386df820482dd108dab6e9e40edadb2bf46abcfe4383f`.
Pinned Sunshine binary SHA-256:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.

- Final stable `bash scripts/validate.sh` exits 0, including 104 indexed fixtures
  and both new lifecycle/proxy test groups. `git diff --check` passes.
- Four menu-owner checks cover inert preparation, exact/bounded replies, joined
  late factory cleanup, stale retirement, runtime revocation during cleanup and
  invalid cross-operation material.
- Two Agent proxy checks cover cancelled delayed preparation replies and a
  mismatched correlation ID, followed by exact joined retirement.
- The real managed Sunshine host probe now uses the production Agent proxy,
  menu backend owner, bounded canonical records and production opaque display
  mapping. It verifies actual client certificate admission, authenticated metadata,
  forbidden pairing/resume/appasset routes, absent plaintext/Web UI listeners,
  busy port, invalid material/proof, revocation and private-state cleanup.
  Its local bridge is in-process; authenticatedLocalXPCFlow and
  authenticatedPrimaryFlow are explicitly false. Its acknowledged runtime snapshot
  is synthetic, not a real normal-menu session.
- Eight actual TLS cases cover valid mutual TLS, wrong pin, unregistered client,
  cancellation, oversized response, bad length, expired host and wrong purpose.
- Normal Control Simulator regressions pass three journeys covering background
  recovery, network loss/cancelled dial and replacement callback isolation.
  Five pairing reliability regressions also pass. They exercise the existing
  Control transport; they do not prove native playback.
- Fifteen native Simulator checks pass (four engine, three launch and eight
  native owner checks). Unsigned Simulator and iPhone SDK builds pass. The six
  framework inventory entries and host/TLS reports match the source fingerprint
  above. Release admission and corresponding-source admission remain false.

Reproducible commands and private outputs:

- `bash scripts/validate.sh`: `/private/tmp/maccompanion-menu-native-validation-final.log`.
- `swift test --package-path Packages/MacCompanionKit --filter nativeBackend`:
  `/private/tmp/maccompanion-native-backend-tests.log`.
- `swift test --package-path Packages/MacCompanionKit --filter nativeProxy`:
  `/private/tmp/maccompanion-native-proxy-tests.log`.
- `python3 Experiments/SunshineMoonlightIntegration/test_managed_host.py --root /private/tmp/maccompanion-sunshine-moonlight-20260926`:
  owned root `managed-host-probe-report.json`.
- Corresponding `test_native_tls.py`: owned root `native-tls-probe-report.json`.
- Corresponding `engine_build.py` for both SDKs, with
  `--test-simulator 8FF65ABB-572E-4EE4-9A9F-F61AA302A586` for Simulator:
  owned root `embedded-engine/provenance-*.json` and native lifecycle log.
- Corresponding `candidate_inventory.py`: owned root framework inventory.
- `MACCOMPANION_SIMULATOR_ID=8FF65ABB-572E-4EE4-9A9F-F61AA302A586 MACCOMPANION_LAB_SUITE=integration bash scripts/verify_simulator_features.sh`:
  `/private/tmp/maccompanion-feature-tests.PijjYe/report.json` and pairing log.

Private test identities, credentials, input and screenshots remain outside Git.
The installed Mac app and physical iPhone were untouched.

## Remaining work

Prove the complete authenticated local-XPC and primary enrollment path with a
real acknowledged menu runtime; compose the normal client and managed host in a
development-only journey; verify native launch, first stable frame, Stop and
reconnect. Define and verify native presentation admission before enabling
keyboard, modifiers, shortcuts, pointer or focused-region input. Complete dependency,
corresponding-source, process/TCC, signing and installation gates, then physical
acceptance. Visible-area bitrate work follows a measured usable baseline.
This checkpoint does not claim that the usable normal-app engine replacement is
complete or ready for installation.
