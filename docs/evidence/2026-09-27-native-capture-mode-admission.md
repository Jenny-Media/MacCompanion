# Menu-owned native capture-mode geometry

## Scope

The authenticated local native backend scope now requires logical width, logical
height and rotation from the acknowledged Desktop snapshot. Its exact runtime
match includes these fields. Missing, malformed, zero/oversized geometry and
unknown rotations fail closed. Encoded pixels cannot substitute for logical
points. The normative local backend specification and manifest-indexed fixture
were updated before this local metadata and lifecycle extension. Existing
application authentication, enrollment signatures, pairing, approvals and grants
remain unchanged.

The menu measures the selected display's current logical bounds, rotation and
capture-mode pixel dimensions before the inert backend factory. The normal
provider uses `CGDisplayCopyDisplayMode` pixel dimensions, rather than logical
or encoded-size fallback. The initial native path requires an unrotated Desktop
whose current logical bounds agree with scope. Capture dimensions are bounded
to 1..32768. Physical display identifiers and capture measurements stay local
to the menu; none is a client-selected Core Graphics identifier.

The owner retains immutable source-content geometry with the exact backend and
passes it to the factory. It rechecks physical display mapping and geometry
around asynchronous preparation/activation and through the existing watchdog.
Missing or changed capture geometry revokes the process permit and drains the
backend. A factory result arriving after a geometry change is retired before
public-certificate preparation. The experimental Sunshine adapter also checks
that its prepared authority uses the expected encoded dimensions.

This measures source capture mode and the expected encoded geometry. It does
not measure an actual Sunshine sample's aperture/image placement or constrain
an enrolled client's native launch request to those dimensions. Those facts
must be joined before native input admission. The current backend keeps native
keyboard, mouse and controller routes disabled; the Mac runtime input pause
also remains latched.

## Verification

Twelve focused Mac tests passed: ten menu backend/capture tests and two Agent
proxy tests. Cases include Retina mode pixels distinct from logical bounds,
invalid/missing capture mode, changed bounds, unsupported physical rotation,
mandatory canonical scope geometry, wrong logical/rotation scope, capture-mode
change while the factory is suspended, and active capture-mode loss. The latter
two verify immediate permit revocation and exactly one backend retirement;
late-factory credential preparation remains zero.

Stable Xcode 27.0 (`27A266a`) repository validation exited 0, including all 105
indexed fixtures. Private log:
`/private/tmp/maccompanion-native-capture-validation.log`.

Both unsigned SDK component builds passed, as did all fifteen Simulator
component tests. All six framework binaries match the refreshed inventory.
The candidate input SHA-256 is:
`b2160e950f447f9e83bde34802a07a4c3ae1f9da2dae5a8018d8b78efe9a87bf`.
The inventory retains `releaseAdmitted: false`.

The isolated managed host probe now derives its Desktop descriptor through the
normal Mac provider. Its real certificate admission, sealed routes/listeners,
invalid proof, port conflict, revocation and cleanup checks pass at that same
candidate. This probe verifies native HTTPS launch; it does not decode video.
Private report:
`/private/tmp/maccompanion-sunshine-moonlight-20260926/managed-host-probe-report.json`.

The signed authenticated primary/XPC host lane passed all four stages, including
native HTTPS launch, two lease renewals, Stop preserving Observe and verified
cleanup. The actual menu measurement was capture 5120×2134 pixels, logical
2560×1067 points and expected encoded 1920×800 pixels. Its report binds the same
candidate and explicitly verifies the structured capture measurement.
Private report:
`/private/tmp/maccompanion-agent-xpc-evidence.kk5k0oud/native-report.json`.

The first host attempt completed native launch but its evidence parser required
the new measurement as a standalone exact marker, while the emitted line also
contains dimensions. That report failed with cleanup verified. The parser was
corrected to require the complete bounded measurement grammar, then the host
lane and full stable validation were rerun successfully. Failed report
`/private/tmp/maccompanion-agent-xpc-evidence.f1tb0q7p/native-report.json`
is not passing evidence.


The refreshed signed Simulator journey passed one native journey test, zero
failures, with two visible native frame/Stop/restart cycles and same-primary
Observe after each Stop. Both cycles verified the menu capture-mode measurement
above through normal UIKit owners, real pairing, primary TLS and signed Mac XPC.
Bootstrap media remained continuous. Cleanup verified; native input remained
false. Private report:
`/private/tmp/maccompanion-agent-xpc-evidence.k7yaftdk/signed-simulator-report.json`.
The combined app/harness/helper fingerprint is:
`3d7c1148e1ec6657f8726a71997051043337de6eb96f02a5262791d80a54e997`.

A preceding Simulator attempt at the same native candidate passed its first
frame/Stop cycle but timed out waiting for the second Control request to become
active. The second Desktop descriptor was prepared, but no second native backend
factory or capture measurement was reached. Cleanup verified. The unchanged
candidate's repeat passed both cycles. This does not identify or repair the cause
of that pre-native restart failure, and no general restart reliability claim is
made. Failed private report:
`/private/tmp/maccompanion-agent-xpc-evidence.3oja3ort/signed-simulator-report.json`.
Further startup diagnostics/acceptance remain necessary alongside the native
presentation work.

## Remaining work

The host must join actual backend sample geometry and image placement with this
current capture mode and the active enrollment. A correlated native presentation
acknowledgement must then bind the current backend, Control and surface revisions
before either input gate opens. The client must use the admitted inner source
rectangle for its existing pointer/trackpad controls and enable keyboard,
modifier, shortcut and focus controls under the same permit, fencing loss/Stop.

Both native input gates remain closed. Rotated native playback/input, all Stop
suspension points, permanent dependency/source/process/TCC admission, normal-app
composition/installation and physical iPhone acceptance remain open. This is a
capture measurement checkpoint, not completion of the usable engine replacement.
