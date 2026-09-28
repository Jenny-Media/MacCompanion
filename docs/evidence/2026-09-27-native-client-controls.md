# Native client keyboard, shortcuts and pointer controls

## Implementation

The normative native lifecycle specification and its sole manifest-indexed fixture
were updated before implementation. Three new lifecycle cases cover separate input
admission, revocation and failure/retry generation isolation. A video frame alone
still cannot enable input. There remain 109 indexed fixtures; authentication,
pairing, approvals and enrollment signing vectors are unchanged.

The normal UIKit native owner consumes the exact typed primary presentation
receipt. An affirmative receipt must match the current session, authorization
epoch, surface/revisions, renderer generation, encoded size and admitted Desktop
logical dimensions. After awaiting it, the owner rechecks the original deadline,
current binding, actual renderer readiness and foreground visible view. It stages
trusted capture/encoded/logical geometry on that exact view before admitting input.
Observation-only receipts remain input-disabled.

The normal product activates its existing relay and controls only while this owner
remains current. Every keyboard and pointer emission checks admission again.
Stopping or losing authority clears admission and geometry. Encoded-size changes
also invalidate staged geometry. The native pointer mapper excludes image padding.
Direct iOS keyboard input retains the existing grant checks and secure-focus
refusal. Native Desktop does not initiate a focused-region capture transition for
ordinary keyboard use; App/Window capture requires its own admitted enrollment.

The existing keyboard accessory was created with zero height while automatic
sizing was disabled. Giving it a 44-point initial height and enabling sizing makes
its physical-key row and Hide Keyboard button visible. The live acceptance now
requires that button to dismiss the keyboard successfully. The shortcuts test uses
the direct shortcuts control and selects the sheet's Copy action unambiguously.

The experimental host sink calls the native posting authorization before counting
delivery. This traverses the real runtime/backend/process/current capture-sample
permit; it records a count and does not post system keyboard or pointer events.

## Verification

Candidate source input SHA-256: `fb4271606d4d19de227dc6af206339af8b1bfb556c0f8bd59c0a9b86de30ed13`.
Final `bash scripts/validate.sh` passes on stable Xcode 27.0, including all 109
indexed fixtures, golden crypto vectors, package/platform and policy checks.
Both iPhone and Simulator SDK candidates bind this source. Fifteen Simulator
component tests pass. The six-framework development inventory matches hashes and
retains release admission false. Its fields distinguish conditional native input
admission from the still-disabled permanent normal-app composition.

The final live journey passes from
`/private/tmp/maccompanion-agent-xpc-evidence.p4t4raho`: one test, zero failures,
two visible native sessions. Each session requires separate host counter advances
for pointer input, direct iOS typing, Shift+Tab and Copy; keyboard dismissal, Stop,
fresh restart and same-primary Observe are also checked. The report records
nativeInputAdmitted, nativeKeyboardAndPointerVerified and cleanupVerified true.
Combined source/helper/harness SHA-256: `e41c84b730e14434505e79e702feea361f3af54541e59e1f01ede41cc4a8be62`.

Both cycles measured 5120×2134 capture pixels, 2560×1067 logical points and
1920×800 encoded video. Trusted receipt geometry is used for pointer mapping.
Initial attempts exposed a keyboard/menu transition issue, the missing accessory
row and an ambiguous Copy test selector; the final run includes their corrections.
Generated caches from those terminal, cleanup-verified attempts were reclaimed;
products, logs and result bundles were preserved.

Private evidence:

- `/private/tmp/maccompanion-native-client-input-final-validation.log`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/logs/embedded-lifecycle-tests.log`
- `/private/tmp/maccompanion-native-client-input-live-simulator-verified.log`
- `/private/tmp/maccompanion-agent-xpc-evidence.p4t4raho/signed-simulator-report.json`

## Remaining work

Native foreground/connection-loss acceptance with input enabled remains next.
Permanent source/dependency/process/TCC admission, normal-app composition and
Mac/iPhone installation remain open. Native focused App/Window capture and
visible-area bitrate optimization remain separate pending work. This checkpoint
uses normal first-party UIKit/session owners with an experimental native adapter;
it does not establish actual CGEvent posting, installed-product behavior, physical
iPhone acceptance or release readiness.
