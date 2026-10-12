# Native visionOS client

Issue [#8](https://github.com/Jenny-Media/MacCompanion/issues/8) adds a native
visionOS application for Apple Vision Pro. Implementation starts from main
`c6f3bec145f3422691301dc02e530834a8cc1fca`. The approved test order is dependency
and input feasibility, implementation and Simulator verification, then final
acceptance on the user's first-generation Vision Pro.

## Platform and transport

The application uses SwiftUI system windows and native UIKit surfaces, compiled
with the visionOS SDK. Each Desktop or Terminal window has an immutable saved-Mac
selection, a unique identity, its own transport and input ledger, and independent
closure and recovery. Opening the same Mac twice creates separate sessions.
The iPhone's Trackpad mode and saved default are preserved; visionOS offers
Desktop and Terminal.

Desktop reuses the iPhone's pinned Citadel SSH owner to forward Screen Sharing
through the remote Mac's loopback address. Host-key confirmation precedes
authentication. Rejected or changed keys close the connection. There is no
plaintext fallback. Terminal uses the same SSH/PTY owner and SwiftTerm's native
UIKit frontend. No historical Agent, custom pairing service, capability authority,
relay or helper is linked into the application.

The normative contract is
[native-visionos-client.md](../spec/capability-protocol/v0/native-visionos-client.md).
Geometry, terminal admission and physical-key traces are indexed exclusively by
`spec/fixtures/manifest.json`.

## Input, privacy and views

Brief system selection performs a click; pinch movement scrolls naturally and
a stationary hold opens target actions. Right Click, Double Click, one-shot Drag
Item and Cancel use the saved intentional target. The native toolbar exposes
Keyboard, Displays, temporary Adjust View and More. Fit, zoom and pan are local
and have button alternatives. Supported physical pointers retain conventional
click, drag, hover and wheel input. Continuous eye tracking is not requested. Keyboard composition
stays local until committed; cancellation, focus loss and lock discard it.
Each owner releases only its admitted keys and buttons. Terminal emulator query
replies remain possible in an unfocused connected window, while new user input
requires a key window in its owning active connection scene. Lock and suspension block both.

Fit preserves the real framebuffer's aspect ratio. Wide and ultrawide frames,
including 3440×1440 and 5120×1440, render in standard windows. Resizing, zoom and
pan change local presentation, not the remote display resolution. Apple's
[current developer response](https://developer.apple.com/forums/thread/829696)
says curved windows are unavailable to third-party apps. Curvature and virtual
monitor creation are outside this implementation; no private API or immersive
scene substitutes for them.

App unlock uses LocalAuthentication with device-appropriate Optic ID or passcode
wording. Each presenting scene registers its own privacy cover above sheets.
Background or interrupted windows clear their frames and sensitive input drafts.
Reconnect is explicit after an unfinished connection is interrupted.

Saved-machine metadata and merge/tombstone behavior reuse the existing model.
iCloud sync remains opt-in and requires the exact already-authorized shared
Keychain group in a signed profile. A missing group fails closed instead of
creating another metadata namespace. Credentials, private keys, trusted server
keys, custom input and sensitive drafts remain device-local.

StoreKit uses the presenting window scene for purchase confirmation. Free/Pro
policy is shared with existing clients. Actual purchase, restore, cross-platform
entitlement delivery and distribution remain separate acceptance checks.

## Reproducible development build

The provisional deployment floor is visionOS 26.0; current automated runtime
checks use visionOS 27 with stable Xcode 27.0 (27A266a). The supported floor must
be exercised before release. Dependencies retain the existing exact source pins:
LibVNCClient 0.9.15, OpenSSL 3.5.8, the recorded Citadel patch set and SwiftTerm.
No dependency source was changed to obtain visionOS support. Existing GPL and
Apple distribution/corresponding-source gates remain open.

Use a clean LibVNCClient checkout at the recorded revision and the checksum-bound
OpenSSL archive, with output outside the repository:

```sh
python3 scripts/build_direct_visionos.py \
  --source /path/to/pinned-libvncserver \
  --openssl-archive /path/to/openssl-3.5.8.tar.gz \
  --output /private/tmp/maccompanion-visionos-sim \
  --sdk xrsimulator
```

Use `--sdk xros` in a separate output directory for unsigned device-SDK
compilation. This does not contact or install on a device. `--probe` selects the
disposable feasibility application under `Experiments/VisionOSFeasibility`;
normal application builds never include that experiment. `--prepare-only`
generates the project and resolves verified dependencies without building it.

The builder compiles platform-native OpenSSL and LibVNCClient, uses the pinned
package resolution and verifies package checkouts. `build-report.json` records
source hashes before/after the build, toolchain, package/source provenance and
the executable hash. Temporary development identities are
`dev.maccompanion.visionos.client` and `dev.maccompanion.visionos.probe`.
Simulator signing is ad hoc with a local test Keychain group. Permanent IDs,
provisioning and shared cloud-group entitlement are not admitted by this builder.

Run `bash scripts/validate.sh`, then the generated `MacCompanionVision` scheme's
`VisionClientTests` and `VisionWindowUITests` on a visionOS Simulator. Tests use
synthetic loopback SSH/RFB peers, fresh local records and the indexed fixtures.
The DEBUG UI test launch argument `--vision-qa-empty-library` selects a fresh
temporary library without modifying the user's saved Macs. Captures, credentials,
logs, results and generated projects stay outside Git.

## Development verification checkpoint — October 10, 2026

Dependency and input feasibility passed before client implementation: the pinned
dependencies compile for both native Simulator and device SDKs, and the disposable
probe's two Simulator interaction tests pass. The normal client builds also pass
on stable Xcode 27.0, with 150 application inputs verified before and after each
build. The normal client never links the probe.

The following evidence is retained outside Git:

| Check | Result | Evidence |
| --- | --- | --- |
| Required repository validation | Passed, including 135 indexed fixtures and the native visionOS input contract | `/private/tmp/maccompanion-visionos-validation-20261011.log` |
| Native client hosted tests | 16 passed, including SSH trust, independent owners, interruption, IME, held input and actual encrypted 3440×1440/5120×1440 frames | `/private/tmp/maccompanion-visionos-client-sim/client-tests-settings-final.xcresult` |
| Native Settings UI | Passed in the final focused bundle | Same final bundle |
| Native multiwindow UI | Passed: two Desktop windows and one Terminal window for the same Mac; closing Terminal preserves both Desktop windows | `/private/tmp/maccompanion-visionos-client-sim/client-tests-final.xcresult` |
| iOS regression suite | 203 passed, 13 optional capture checks skipped, no failures; synthetic OpenSSH export interoperability also passed separately | `/private/tmp/maccompanion-visionos-ios-regression/QA/Results.xcresult` |
| Native macOS compilation | Passed | `/private/tmp/maccompanion-visionos-mac-regression/build-report.json` |
| macOS runtime regression comparison | 53 of 54 tests passed through an isolated signed LaunchServices runner, including native focus and two concurrent SSH sessions. The remaining accessibility test also fails against unchanged main in that runner | `/private/tmp/maccompanion-visionos-mac-regression/QA/baseline-comparison.json` |
| First-generation Vision Pro installation and launch | Passed on visionOS 27; native process observed after launch | `/private/tmp/maccompanion-visionos-final-signed-c13owelt/` |

The earlier combined native client bundle contains an obsolete failing Settings
scroll check, repaired and passed in the final focused bundle. There are 18
distinct passing native client checks across those two bundles, not one complete
18-test result bundle. macOS's ordinary Xcode hosted invocation stalled before
test execution while preparing its IDE session; the standalone comparison does
not establish a completely passing hosted lane. Its remaining test is
`testUnreadableImportedLibraryKeepsDiskKeyManagementAccessible`, which times out
looking for native accessibility elements on both the current source and pulled
main. No app or test assertion was weakened to make it pass.

Final headset installation used an existing, unexpired development profile and
certificate that already include this device. The signed copy retains a temporary
development bundle identifier and the existing authorized iPhone metadata group;
sync remains opt-in. Its receipt binds the original unsigned source report,
compiled/signed executable hashes, profile, signing leaf, entitlements, Info.plist,
installation and launch records. No permanent identity, new provisioning profile
or distribution configuration was created. Installation and launch are verified;
interactive sign-in/input, signed cross-device metadata delivery, real StoreKit
and TestFlight acceptance remain open.

The first interactive headset check exposed two failures: the user can move
the Desktop pointer, but selection does not click, and the Desktop Keyboard
control shows an empty input bar without the system keyboard. This checkpoint
failed physical input acceptance.

The correction routes spatial taps and drags through one exclusive selection
sequence, tolerates small hand movement, and sends each click as an ordered
press/release group. The hardware-wheel recognizer admits only scroll events.
The native text view requests first-responder focus after attachment; canvas
responder cleanup preserves that activation, while text-responder loss releases
held input and discards uncommitted composition. Five selection traces were
added to the existing manifest-indexed fixture.

The final focused Simulator bundle passes all 18 tests, with no failures or
skips, including 17 hosted client/privacy checks and a real native-window UI
connection to the encrypted synthetic SSH/RFB peer. The UI check verifies
exactly one remote press for a stationary selection, drag/release, and the
visible visionOS system keyboard in its separate owning app. Evidence:
`/private/tmp/maccompanion-visionos-client-sim/input-fix-final-tests.xcresult`.
The earlier multiwindow and Settings UI checks also passed during this repair;
there are 20 distinct passing native checks across focused bundles.

Simulator coordinate synthesis landed one diagnostic tap in the letterbox;
native element selection correctly reaches the image center. The UI harness
also explicitly reconnects if the OS password-save dialog interrupts sign-in.
Neither letterbox rejection nor interrupted-login admission was weakened.

Normal Simulator and device-SDK reports were refreshed against the final source.
The corrected app is signed with the same existing profile/certificate and
installed for the next physical retest. Its source, compiled/signed code,
entitlements, installation receipt and attempted-launch records are retained outside Git under
`/private/tmp/maccompanion-visionos-input-fix-signed-vgl4ufa_/`.
CoreDevice remote launch returned an unavailable-service error and a retry timed
out. Installation is verified; launch of this corrected build is not yet verified.
The user has been asked to open it manually and retest clicking and the keyboard.
The user currently has no headset access, so those checks and remaining physical
acceptance are pending. No further hardware checks are being attempted.

## Interaction redesign — October 11, 2026

The approved [interaction plan](visionos-interaction-redesign-plan.md) now has a
native implementation. Its event contract is normative in
`spec/capability-protocol/v0/native-visionos-client.md`; the single manifest-indexed
fixture covers fourteen interaction traces, five sampled-distance cases, natural
wheel direction, jitter, wide geometry and independent held-input owners.
Six visible-target cases prevent toolbar actions from using a previous display
or a cursor hidden by local adjustment. Seven native packet cases cover bounded
coalesced movement and exact signed 16.16 displacement. A generated two-display
peer negotiates the existing native extension; hosted tests verify actual decoded
crop changes, visible action targets, native packet bounds, distance totals and
pause/resume without replay or connection loss.
The configurable More-menu Right Click uses the same visible target as Desktop
Actions; the session cannot dispatch an unbound cursor click. Three indexed
physical-wheel boundary cases exercise the actual UIKit adapter for ending,
cancelling and failing over letterboxing. They verify fresh native targets and
no fractional fallback travel carried into a later gesture.
The adapter retires only scroll state; late wheel callbacks preserve a physical
selection's held button until that selection finishes through its own recognizer.
Wheel intent also binds its initial remote target to the owner generation, crop,
viewport and local presentation. Seven indexed lifecycle cases invoke the actual
UIKit selector on both transports: owner release, display selection, resize,
pause/resume, adjustment, presentation change and hand handoff. Remaining updates
cannot restart retired scrolling, and a late endpoint cannot finish the hand
selection that replaced it. Fresh input requires another admitted begin.
Nine physical-selection retirement cases cover ended/cancelled/failed mouse
callbacks after owner release, adjustment and Keyboard activation. Explicit
cancellation clears the mouse origin; its late completion cannot release a newer
hand drag, which remains held until its own completion.
Nine magnification cases invoke the actual pinch selector with moving centroids.
The initial anchor stays fixed; completion, cancellation, failure, owner/view
changes and adjustment exit invalidate it. Local zoom generates no remote input;
the explicit owner pause's balanced cleanup is checked separately.

The development app uses native toolbar ornaments. Content and ornaments are
UIWindows in one owning connection scene; a different connection scene cannot
provide input admission. Keyboard requests restore the native content responder.
One press reopens input after a canvas selection, and Done discards composition.
Terminal retains native SwiftTerm scrollback, selection and paste, with Tab,
arrow/Escape keys, one-shot Control/Option, new independent shell and end-current-shell
controls. The library returns to existing windows and offers explicit additional
Desktop/Terminal windows. The native Quick Actions form filters unsupported
Mouse Mode in its preview, Add Action catalogue and restored defaults. Stored
unsupported entries retain their identities; shared iPhone editors/preferences
remain unchanged. Named move buttons, enable/disable and removal keep supported
customization reachable. Native storage/presentation and actual Settings UI
regressions cover defaults and retained entries.

The generated SSH/RFB peer changes decoded pixels after click, scroll, drag and
committed keys. It records bounded synthetic event metadata rather than actual
user input. Native UI tests use the regular library, login and trust workflow;
they verify a real virtual-keyboard key, Terminal mouse press/release reports,
modified arrows and independent window closure. A compact 600×420 window uses
accessibility-size text and exercises scrollable actions, adjustment, keyboard
and Disconnect. A host-provided standard steady-cursor sequence keeps Terminal
UI tests deterministic without changing the app's normal cursor behavior.

Development checks are retained under
`/private/tmp/maccompanion-visionos-redesign-20261011/`. Final delivery requires
all checks in `review/contract.json`, their binding to one unchanged source state
in `review/check-results.json`, three Desktop UI repetitions, and a fresh two-stage
review. Prototype results in that folder establish individual development steps;
they do not substitute for the final bound gate. Builds, `.xcresult` bundles and
exported screenshots remain outside Git.

The continued repair-and-review cycle records its protected baseline, required
checks and independent review under
`/private/tmp/maccompanion-visionos-review-cycle2-20261011/review/`. It requires all
34 discovered native cases, three Desktop journeys and unchanged-source binding
for the complete required check manifest. The prior cycle's reports remain
historical evidence; they do not establish the continued cycle's final gate.
Seven indexed hand-pan boundary cases cover immediate reversal after overshoot
in both axes, diagonal travel, nonzero origins, cancellation and a fresh
selection baseline through the native canvas, with no remote input.
Forty-two indexed physical-press cases exercise actual UIKit touch admission and
primary/secondary completion or delayed drag begin. Owner release, resize/crop,
adjustment, zoom roundtrip/Fit, Keyboard and hand handoff retire old presses;
cancelled/failed/unadmitted taps send nothing. Each case also admits a fresh
touch and verifies its conventional input through the native SSH/RFB peer.

| Scenario | Evidence layer and boundary |
| --- | --- |
| Click/jitter, hold/cancel, right/double click, scroll and armed drag | Indexed traces, actual native-window UI and bounded SSH/RFB events |
| Equal movement at different sample rates and natural direction | Actual controller through the hosted renderer/session to the real peer; signed remainder and wheel-mask fixtures |
| Modified clicks, physical drag and cancellation | Native responder/physical-adapter hosted tests and held-key fixtures; actual peripheral recognition remains final hardware work |
| Local zoom/pan/Fit, clamping and stale targets | Indexed geometry, hosted native canvas and normal/compact native UI |
| Keyboard reopening and committed typing | Actual responder plus a virtual “x” key in `com.apple.RealityKeyboard`; composition cancellation is hosted UIKit coverage |
| Terminal keys, modifiers, paste, mouse reports, scrollback/selection and links | Real SSH, native SwiftTerm and native UI; links require explicit confirmation |
| Multiple owners, new shell, reuse and closure | Native UI plus hosted registry/input-isolation checks |
| Interruption, pending hold and resize | Hosted owner cleanup/timer/geometry checks; native privacy and metadata checks retained |
| Standard, 3440×1440 and 5120×1440 | Real encrypted frames, native renderer and mapping fixtures; local view changes keep the remote size |
| Compact controls, larger text, forms and Settings | Native UI with accessible labels/button alternatives; actual VoiceOver navigation and direct-finger recognition remain pending |

The Simulator loop exposed and corrected normalized hand-displacement handling,
natural wheel direction, native ornament focus, keyboard reopening and local
adjustment retirement during menu use. Those failures have explicit regression
coverage. Simulator success still requires the bound final report.

The provisional visionOS 26 floor has no installed runtime here. First-generation
visionOS 27 physical acceptance, actual two-hand magnification, direct-finger input,
dictation/system IME, VoiceOver/peripheral recognition, natural-scroll comfort and
fatigue remain pending. Reduced Motion uses native controls; Terminal requests a
steady cursor when that public environment setting is enabled. Simulator-generated
input does not establish those hardware/modalities results.

Flat wide/ultrawide support remains. Apple's public guidance and installed SDK
preflight provide no supported third-party curved-system-window API; no private
window settings or immersive replacement are used. Signing, cloud delivery,
StoreKit, TestFlight and release keep their independent gates.

## PR #12 full-review repairs — October 11, 2026

The follow-up candidate integrates main through
`3ec3942303e96aa31f643fd1920f20e8d8df7814`, retaining the iOS text composer and
Copy Text from Screen changes. Seven accepted review findings have dedicated
regression coverage: retired keyboard releases, initial Terminal output, owning
scene sensitive-state cleanup, metadata-sync consent, Free Mac selection,
library recovery, and current-library checks when saving an old editor snapshot.
The fresh review also added persisted-port coverage: blank and whitespace SSH
input uses 22, Screen Sharing uses 5900, and invalid values preserve storage.
Further indexed regressions retain immutable import/export presentation identities
across replacement, background, inactive and locked callbacks. A retired success,
cancellation or error cannot read a file or clear a newer export. A normal native
UI journey opens, cancels and reopens the system Files importer. Unsupported
retained Copy Text actions remain stored but are absent from visionOS presentation
and restoration, alongside Mouse Mode.

The Terminal window installs a generation-scoped output buffer before connecting.
It preserves early banners and protocol queries until the native SwiftTerm view
attaches with a usable layout, drains once in order, and ends the connection explicitly if its 1 MiB
bound is exceeded. Old-shell output and stale detach callbacks cannot affect a
replacement receiver. The native connected-only layout is retained after a
pre-mounted layout crashed in a normal Simulator UI journey.

Twelve hosted regressions exercise native responders, the real SSH/RFB peer,
bounded startup output, import passphrase scene cleanup and the actual library
save path. Four additional UI journeys inspect the full sync disclosure, cancel
and confirm opt-in, choose another retained Free Mac, reopen the Files picker,
and reach/cancel the separate cloud-deletion warning and confirmation. The Terminal hosted
test asserts and renders its startup banner, while the normal UI journey records
native attachment before input. Development checks passed before the
complete stable-state gate; final evidence for this cycle is stored outside Git
under `/private/tmp/maccompanion-pr12-seven-fixes-20261011/review/`. The gate
requires all 50 discovered native cases, the full repository validation, both
unsigned SDK builds and a fresh two-stage independent review on one unchanged
source fingerprint. Earlier reports do not substitute for that gate.

Multiwindow Simulator XCTest screenshots may crop another scene's camera view.
The startup hosted test captures pixels directly from the native Terminal layer;
the normal UI journeys retain the actual consent and library accessibility trees
alongside their assertions. Camera captures are diagnostics, not proof of a
specific window's content.

Owning-scene background and actual lock retire SSH drafts, pickers and pending
operations. Temporary authentication inactivity preserves its context; completion
still requires the current generation and an active, unlocked owning scene.
Settings clears unsaved quick-action drafts on the same privacy boundary.
Settings also exposes the existing Delete Mac Data from iCloud workflow. Its
warning keeps local Macs and asks users to disable sync on other devices first.
An immutable confirmation identity and live scene/unlock/busy checks prevent
cancelled, stale or interrupted alerts from committing. Indexed hosted cases
exercise actual deletion through injected in-memory storage and verify local
record bytes remain unchanged; normal UI tests cancel without any real deletion.
Unreadable library storage exposes Retry and disables creation/editing; retrying
does not overwrite the unreadable file. A removed editor snapshot receives the
same current Free/Pro creation check as a new record.

No physical Vision Pro is contacted in this repair cycle. Optic ID/export,
actual hand/peripheral recognition and the original headset click/keyboard
acceptance remain final physical work, alongside the gates below.

### Native hardware-key cancellation

UIKit may cancel a hardware press instead of ending it while its responder stays
focused. Desktop now binds captured press identities to the current input
generation and balances the whole canceled key owner once. Old endpoints cannot
release a fresh press of the same HID usage; ordinary modified clicks retain
held modifiers. Terminal owns its press identities, stops frontend repeat and
balances negotiated Kitty releases on cancellation and owner cleanup. Retired
endpoints cannot stop a newer repeat or duplicate a release.

Five additional hosted Simulator regressions invoke actual native press handlers
through synthetic UIKey/UIPress subclasses, over real SSH/RFB and SSH PTY. The
manifest-indexed cases cover focused cancellation, modified clicks, duplicate
endpoints, fresh same-HID input, repeat shutdown and negotiated release. The full
required suite is 50 hosted cases and nine normal UI cases, with no required skips.
The canvas case also proves old Control flags cannot recreate retired modifiers,
and late endpoints cannot release a fresh same-HID key or newer pointer hold.
The new complete stable gate and fresh review evidence live outside Git under
`/private/tmp/maccompanion-pr12-keyboard-cancel-20261011/review/`; results from
earlier repair cycles cannot substitute for this candidate's gate.
The requested Xcode 27.1 RC checks and stable Xcode 27.0 checks use separate
SDK build and validation scratch directories. Both lanes must pass on the
same source state; RC results alone remain provisional.

SwiftTerm's pinned UIKit `pressesEnded` is public but not open. Native visionOS
development builds admit exactly a public-to-open declaration change using
original and adapted full-file hashes in the dependency policy. The complete
Git/pin/origin/source tree is verified before writing, the original file mode is
preserved, and actual adapted provenance is checked before and after compilation.
Other platform builders retain default strict clean-checkout verification. No
frontend implementation, package revision, authentication or wire protocol is
changed. Distribution and actual hardware acceptance remain separate gates.

## Final physical acceptance

Simulator checks precede final first-generation Vision Pro testing. iOS/macOS
regression results remain separately recorded above, and the incomplete macOS
hosted lane must be resolved before release. The device must run the supported
OS and be paired for development; signing must use an authorized identity and
profile.

Verify Desktop and Terminal against built-in services on a real Mac, including
first-use and changed SSH trust, sign-in, display selection, precise selection,
dragging, scrolling, physical keyboard/pointer and real IME composition. Exercise
two concurrent sessions, switching focus with held keys/buttons, reconnect and
closing one owner. Check spatial resizing, text readability, accessibility,
Optic ID/passcode, interruption, recovery and first-generation performance for
wide/ultrawide frames.

Then separately verify signed iPhone–Mac–Vision Pro metadata edits, conflicts,
deletions, restart and offline recovery without secret propagation. Real StoreKit
purchase/restore and TestFlight availability require their own evidence. A
Simulator or unsigned device-SDK pass does not establish these results, and the
issue remains open until its physical acceptance checks are met.
