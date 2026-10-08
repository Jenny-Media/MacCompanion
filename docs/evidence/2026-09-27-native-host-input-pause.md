# Host input pause before native presentation

## Change

The normal client already disables native input. The Mac now independently
pauses input before native backend preparation. Its serialized runtime first
validates the exact acknowledged Desktop fence, latches the pause, and releases
held input. Only successful release allows display resolution and backend
factory work to proceed. A release failure invokes full safety cleanup;
no private backend is created on a failed pause.

The pause rejects pointer, button, scroll, physical key, modifiers, text and
reset at both runtime input entry points. Exact pause replay does not repeat
release. Renewal preserves the pause. Native preparation, activation, health,
retirement and legacy acknowledgements cannot restore legacy input. A fresh
Control install starts without the latch.

The normal Mac adapter supplies this mandatory pause callback to the menu-owned
native backend. An abstract runtime that does not implement the pause rejects
native preparation. The experimental managed-host bridge uses the same runtime
method. The capability and menu runtime specifications and the existing
manifest-indexed backend fixture were updated before behavior changed. No wire
fields, signing transcripts, pairing or approval semantics changed.

## Evidence

Stable Xcode 27.0 (27A266a), macOS 27.2; dedicated iOS 27.0 Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

Native candidate input SHA-256:
`839d438d96a8417677621939e50dff16128a84032d0a69e6b981883e75213723`.

Final `bash scripts/validate.sh` passed, including five native backend tests and
two runtime pause regressions. The checks cover all seven input payload kinds,
both entry points, exact-fence rejection, idempotent release, renewal, release
failure cleanup, no backend on pause failure, and fresh Control installation.
The index validates 104 JSON fixtures. `git diff --check` passed.
Private full validation log:
`/private/tmp/maccompanion-native-input-gate-validation.log`.

The authenticated continuous-bootstrap Simulator report
`/private/tmp/maccompanion-agent-xpc-evidence._t_hbf5j/signed-simulator-report.json`
passed one UI test with zero failures and verified cleanup. Two actual native
displaying/pixel checks and complete Stop/restart cycles pass through normal
UIKit owners, real pairing/primary TLS and signed Mac XPC. Both use the normal
Mac Desktop geometry. Same-primary Observe remains available; no native input
was admitted. Combined app/harness/helper source fingerprint:
`fc441a07c2e4e7267291f7743e58bfcdfc047aecbe9e785113d5eaa69d4921aa`.

The separate signed host lane passed all four stages and verified cleanup in
`/private/tmp/maccompanion-agent-xpc-evidence.knij3c0q/native-report.json`.
Native enrollment, actual mutual TLS/Desktop launch, two Control renewals and
joined Stop preserving Observe pass at the same candidate hash. Local XPC source
hash: `51cbe23531dba892e2bd0967bb7db3381b6f746ae223276334a1b419ef791660`.

Both unsigned SDK component builds were refreshed. All fifteen native Simulator
component checks passed (four engine, eleven adapter/owner/TLS). The six-framework
inventory matches the candidate hash and retains `releaseAdmitted: false`.

## Next integration step

Native presentation acknowledgement is not yet admitted. The next change must
join the current authenticated enrollment, native generation, presented capture
geometry and host input gate with an exact correlated receipt. It must revoke
input on native loss/Stop and reject stale, mismatched or late presentation.
Content bounds, viewport mapping, keyboard/modifier/shortcut and focus coverage
must then be tested through the normal client controls before enabling native
input in the candidate.

Software test custody/consent, generated bootstrap/indicator/input effects and
disposable signed helpers remain substitutes. Permanent dependency/process/TCC
admission, normal target composition, signed installation and physical acceptance
remain open. Installed normal apps and the physical iPhone were untouched.
