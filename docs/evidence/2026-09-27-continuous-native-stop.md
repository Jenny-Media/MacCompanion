# Continuous bootstrap Stop and native restart

## Repair

The earlier finite-bootstrap checkpoint displayed native video but left a
continuous legacy-stream shutdown race open. The iOS role owner closed both
sockets immediately upon submitting Stop. A Mac media publication already in
flight could then fail its ownership acknowledgement and invalidate the menu's
XPC connection, preventing a fresh Control session.

The client now fences input before the Stop send can suspend. Established role
connections remain open during the bounded ending phase. The renderer is
blanked; complete media records still pass exact session/epoch/surface admission
but are discarded without decoding, presentation, acknowledgement or input.
Correlated completion, rejection, request timeout, primary loss or role failure
closes the pair. An incomplete handshake is cancelled so it cannot activate
after Stop. A failed Stop send does not restore input; a fresh authenticated
acceptance is required. Stop does not emit a late input reset.

The host fences native admission and revokes the runtime input/capture lease
before waiting for native/WebRTC cleanup. The correlated Stop reply still waits
for the engine cleanup. Existing strict media ownership acknowledgements and
generation invalidation rules are retained.

The client and menu runtime specifications and the existing manifest-indexed
host role data-plane fixture were updated before these lifecycle changes.
No signature fields, signing transcripts, grants or pairing semantics changed.

## Verified snapshot

Stable Xcode 27.0 (27A266a), macOS 27.2; dedicated iOS 27.0 Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

Native candidate source input SHA-256:
`11caac034b66d8b269c3602c5549299a08c66977d735c4e6198519e711ec0218`.
Pinned Sunshine binary SHA-256:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.

The finalized continuous-bootstrap report is
`/private/tmp/maccompanion-agent-xpc-evidence.e1gh2imw/signed-simulator-report.json`:
one UI test passed, zero failures, cleanup verified. The combined app/harness/
signed-helper source fingerprint is
`79f8c3cca3d03bbfcad7608951dae1ff68bfeb2e7e3445c508c5e65ffdea2ab7`.

The report records two cycles through the normal UIKit workspace, role, surface
and native owners in a generated experimental application:

1. Real pairing, independent Act/Control grants and authenticated primary TLS.
2. Continuous generated legacy bootstrap decode and exact acknowledgement,
   followed by signed Mac XPC enrollment and managed Sunshine Desktop launch.
3. Actual native decode, owner phase `displaying`, and a visible surface pixel
   assertion in each cycle. Native presentation adds no input events.
4. Primary Stop removes the live surface and empties the media queue. Same-primary
   Observe succeeds, no journey failure remains, and the second native session
   starts without pairing again.
5. Both managed host instances and disposable state drain; the verifier reports
   cleanup success. Optional Xcode diagnostics collection is disabled; no manual
   diagnostics intervention was needed for this run.

The signed host lane ran separately after releasing the Simulator host. Its four
stages passed in
`/private/tmp/maccompanion-agent-xpc-evidence.v8ao_hii/native-report.json`, with
cleanup verified. It covers actual enrollment/mutual TLS/Desktop launch, two
Control renewals and joined Stop preserving Observe at the same candidate hash.

Both unsigned SDK component builds match this hash. Fifteen native Simulator
component checks passed (four engine and eleven adapter/owner/TLS); the inventory
verifies all six framework binaries and retains `releaseAdmitted: false`.

Focused regressions passed for failed-send input fencing, exact accepted-session
flow, renderer blanking, strict ending-record validation, no late ACK/reset and
role retention until the ended reply. Host teardown regression also requires
runtime termination before native cleanup starts.

Final `bash scripts/validate.sh` passed with the stable toolchain, including that
host ordering regression and all 104 indexed JSON fixtures. `git diff --check`
also passed. The private full validation log is
`/private/tmp/maccompanion-stop-workspace-validation.log`.

## Limits and next work

This resolves the measured active-stream Stop/restart race in the authenticated
loopback journey. It is not exhaustive evidence for Stop at every handshake,
surface-transition, network-loss or native-preparation suspension. Those paths
must remain fail closed; the passing active-session test is not their acceptance.

Software test custody/consent, generated bootstrap/indicator/input effects and
disposable signed helpers remain substitutes. Native video is actual capture of
the approved physical Mac display. Screenshots and private state stay outside Git.

Native input remains disabled. The next milestone is a specified native
presentation receipt joined to the host input gate, exact capture/content geometry
and viewport mapping, then keyboard/modifier/shortcut and focus coverage. Permanent
dependency/process/TCC admission, normal target composition, signed installation
and physical iPhone acceptance remain open. Neither installed normal app changed.
