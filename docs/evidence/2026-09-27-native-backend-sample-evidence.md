# Actual native capture evidence

## Scope

The managed-host and local-backend specifications and the sole indexed fixture
corpus were updated before adding this metadata extension. Existing pairing,
authentication, approvals, signatures and Observe/Act/Control grants are unchanged.

The experimental Sunshine host now binds both HTTPS launch and RTSP negotiation
to the exact admitted encoded width, height and 60 fps. A different HTTPS launch
mode is rejected in the live host probe. The RTSP restriction compiled and the
matching live stream passed; a mismatched RTSP request has not been exercised.

The pinned Mac capture implementation reports its actual CVPixelBuffer size,
CMVideoFormatDescription size and clean aperture, original capture-mode size,
configured aspect-fit scaling, operation ID, positive sample sequence and Mach
monotonic timestamp. Atomic private reports contain metadata only. The supervisor
sets a private umask; spawn context is cleared and then populated from the exact
managed operation, private report path and expected video mode.

The backend opens the report without following links, checks regular-file type,
owner, private permissions and bounded size, and requires an exact closed,
canonical JSON shape. Unknown/missing keys, malformed dimensions, a partial clean
aperture, wrong operation/geometry, future time and oversized records fail closed.
An empty or stale report remains pending. Freshness is limited to two seconds.
The Mac owner rechecks its exact scope and geometry after asynchronous inspection
and exposes fresh evidence only on the matching active health receipt. The Agent
proxy validates the receipt against its current command. Physical display IDs
remain local; no pixels, credentials or input content enter this record.

The reported scaling setting is the actual AVFoundation output configuration.
Apple documents that [ResizeAspect preserves aspect ratio and fills remaining
areas with black](https://developer.apple.com/documentation/avfoundation/avvideoscalingmoderesizeaspect).
The source-content rectangle still derives from this contract and retained source
geometry; this metadata does not itself prove the client's presented rectangle.

## Verification

Stable Xcode 27.0 (27A266a) repository validation exited 0 with 106 indexed fixtures.
Fifteen focused capture/backend/proxy tests, the process-owner checks and four
real-process supervisor tests passed. The supervisor test's stale two-hour
assumption was corrected to the existing normative four-hour limit; the runtime
lifetime policy did not change.

Both unsigned iPhone and Simulator SDK components built. Fifteen Simulator
component tests passed (four engine tests and eleven adapter tests). All six
framework binaries match the refreshed inventory, which retains
`releaseAdmitted: false`.

Final native candidate input SHA-256:
`286a9f2d39bf4b6aa3bd84e861ffc7ac4cb585f5eccf337ddbaf45cb146189dd`.
Pinned rebuilt Sunshine binary SHA-256:
`c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d`.

The final managed-host probe passed mode rejection, certificate admission,
sealed routes/listeners, port conflict, invalid proof, revocation and cleanup.
The signed host journey passed pairing, native enrollment, actual mTLS launch,
two lease renewals and Stop preserving Observe; cleanup was verified.
Private report: `/private/tmp/maccompanion-agent-xpc-evidence.emnl_5xd/native-report.json`.
One preceding attempt could not write an Xcode cache in the restricted sandbox;
it failed before any journey cases and cleaned up. The authorized rerun passed.

An intermediate candidate passed two visible native frame/Stop/restart cycles
with continuous bootstrap on the dedicated Simulator. Each cycle validated an
actual sample: capture mode 5120×2134, logical bounds 2560×1067, pixel buffer and
format 1920×800, full clean aperture (0,0,1920,800), aspect-fit configured. There
were no bootstrap-install or frame-submit errors in that run. Its source hash
was `1905a6fad7fca6642a0afa98d74153219e66c58efffc08958c5edba96b94e3ea`,
before the supervisor-test correction. Private report:
`/private/tmp/maccompanion-agent-xpc-evidence.cp8vv56t/signed-simulator-report.json`.
The final source-bound Simulator repeat also passed both visible native
frame/Stop/restart cycles with the same measured sample geometry and continuous
bootstrap. The single journey test had zero failures, verified both actual-sample
markers and current capture-mode measurements, and verified cleanup. Native input
remained disabled. Private final report:
`/private/tmp/maccompanion-agent-xpc-evidence.u_i9f98d/signed-simulator-report.json`.
Its combined source/helper/harness fingerprint is:
`15259659376ac4d7c38c8323910b7188e19c6ecae63578b3ee27fff6eff4b2b9`.
The final report binds the native candidate SHA-256 above.

Private validation/component logs remain under `/private/tmp` and the owned
native build root. Reports, source copies, test results and binaries are retained;
only generated intermediates from completed, cleanup-verified runs were reclaimed.

## Remaining admission

This private experimental observation is not a cryptographic producer proof or
native input authority. Both native input gates remain closed. Correlated client
presentation admission must join the exact current backend, Control lease,
Desktop/surface geometry and actually visible client frame before input is enabled.
Then the existing keyboard, modifiers, shortcuts and pointer/focus controls can
be exercised against native playback.

A previous pre-native restart failure remains unexplained; these successful
cycles do not establish general restart reliability. Stop at all handshake
suspensions, focused App/Window capture, permanent dependency/corresponding-source
and process/TCC admission, normal release composition and physical installation
remain open. This checkpoint does not install either normal app on the Mac or phone.
