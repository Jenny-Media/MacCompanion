# Authenticated WebRTC signaling checkpoint — September 22, 2026

This checkpoint targets WebRTC video in the normal MacCompanion apps. It adds
the complete-gathering offer/answer command contract and typed host/client
routing, while the current credentialed media role remains the active video
path. No WebRTC binary is linked into a permanent target and no current-app
video, physical-device acceptance, or release readiness is claimed.

## Completed boundary

- `spec/interactive-control/v0/webrtc-media-adapter.md` fixes the existing
  authenticated primary and Control session as the only negotiation owner.
  Observe and Act grants, input, Stop, original expiry, and revocation remain
  independent. The existing file relay is not a product signaling service.
- Four strict command bodies and seven indexed positive/negative wire fixtures
  cover offer request, complete offer, answer, ready, fingerprint mismatch,
  missing candidate, and unsafe generation. A separate indexed transition
  fixture covers local peer replacement, background return, stale callbacks,
  duplicate signaling, Stop, expiry, revocation, and surface fencing.
- The host primary dispatcher admits these kinds only for its current
  authenticated Control session. It checks the durable grant snapshot around
  each suspended media operation, correlates the answer to the exact offer,
  bounds the answer window, and clears pending media on Stop and primary loss.
  The Agent startup path now carries its optional media provider through
  authenticated menu-authority replacement into the dispatcher. No provider
  is installed in the release composition yet.
- The client Control channel can request an offer for its current surface,
  submit an answer, and publish exact-correlated offer/ready results. A late
  offer after Stop is consumed without reviving the Control presentation or
  closing the otherwise healthy Observe/Act primary. It also discards an old
  surface's offer after replacement while preserving the primary connection;
  submitting an answer or accepting ready requires the current surface fence.

The contract requires WebRTC to finish ICE gathering before exposing local SDP.
It validates candidate presence and the DTLS fingerprint in the transported
SDP. The runtime adapter must still bind that fingerprint to its actual peer,
recheck the active session/surface/expiry on every callback, and drive current
frames into the existing presentation authority. No such provider is installed
yet.
The current Control UI enables input only after a clean frame is visibly
rendered and acknowledged on the existing media role. A WebRTC negotiation
`ready` response cannot satisfy that frame proof. A WebRTC frame-presentation
receipt and its host/client ownership still need a normative contract and
authoritative fixtures before the normal app can switch its active video path.
The Mac app also separates the Agent's authenticated network ingress from the
menu app's ScreenCaptureKit capture. The Agent startup path now accepts a
media negotiation provider, but there is no authenticated local-XPC forwarding
to a menu-owned WebRTC peer yet. Moving the peer into the Agent would require
a different reviewed frame handoff and Screen Recording attribution; this
checkpoint does neither.

A short Mac-to-Mac negotiation with the pinned framework confirmed the wire
shape without retaining SDP: the complete offer and answer contained eight ICE
candidate lines each, one valid SHA-256 fingerprint line each, and were 2,688
and 2,550 UTF-8 bytes respectively. Neither contained
`a=end-of-candidates`; therefore the schema uses the framework's ICE-complete
state as the completion proof instead of requiring that optional line. This
probe did not exercise authenticated product routing or on-screen video.

## Dependency admission evidence

The local 153.0.0 archive still hashes to
`3e3a8946f27510133e3feed04d05fa23505bbe366e977620503bfc7986c2b78f`.
Its ZIP contains a top-level `LICENSE` and per-platform privacy manifests, but
no `LICENSE_THIRD_PARTY` or equivalent notices file. Upstream's
[iOS license generator](https://webrtc.googlesource.com/src/+/96feb2ac1c2f0b3a477807db7a11d10eb5a138bd/tools-webrtc/ios/generate_licenses.py)
references both `webrtc/LICENSE_THIRD_PARTY` and licenses for bundled
third-party components. The [distributor repository](https://github.com/stasel/WebRTC)
describes open build automation and official WebRTC source, but this checkpoint
has not reproduced the 153.0.0 binary from the declared source revision or
assembled exact transitive notices. Its supported-OS, privacy, signing, and
dependency-policy reviews therefore remain open. The existing experiment-only
exception is unchanged.

## Validation and next work

Focused host, client, wire, and local lease tests exercise the new route and
fences. `scripts/validate_fixtures.py` checks all 88 indexed JSON fixtures.
The full `MacCompanionKit` Swift package suite passed with normal local macOS
display access. Inside the restricted task sandbox, one unrelated desktop
test failed because its display lookup returned unavailable; the same exact
test passed with ordinary display access before the full-suite rerun.
The required `bash scripts/validate.sh` was rerun after the changes. It passed
the fixture, dependency-policy, target-topology, privacy, SBOM, and preceding
signing checks, then stopped at the existing absent fixed
`/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler` path. No
aggregate pass is claimed, and that gate was not weakened.

Next, implement the Mac WebRTC peer provider behind the host's optional media
authority and the iOS peer/renderer behind the Control channel. Compose each
with the existing active Control and surface owners, release input on peer
replacement, and test complete-gathering SDP with the actual framework. Finish
binary reproducibility/notices/privacy/signing/dependency admission before
linking the framework into permanent targets. Then run short Simulator and
physical foreground, Wi-Fi, Stop, expiry, revocation, and stale-callback checks
through the authenticated path. Measure offer admission and first current frame
separately. The operator's skipped long physical soak stays skipped.
