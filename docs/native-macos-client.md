# Native macOS VNC and SSH client

The approved macOS goal extends the direct client decision in
`docs/remote-desktop-mvp.md`. Both clients connect to built-in macOS Screen
Sharing for Desktop, and Remote Login for SSH Terminal. iPhone also retains its
Trackpad & Keyboard mode; macOS exposes only Desktop and Terminal.
No Mac Companion host, Agent, local XPC, pairing, capability grants, or helper
is instantiated by this client. The legacy implementation remains historical.

## Shared behavior

Share the saved-machine model, validation, discovery, VNC socket/protocol owner,
SSH authentication and host verification, key library, Pro entitlement policy,
preferences, and cloud merge implementation. Preserve the existing iOS screens
and gestures. macOS uses SwiftUI and AppKit, not Catalyst or a local shell as a
substitute for SSH. The native Terminal surface uses the pinned SwiftTerm AppKit
frontend and the same Citadel SSH/PTY owner as iOS.

Each session window owns an immutable machine/mode selection and its own VNC or
SSH connection. Multiple windows may use different machines or modes, including
Desktop and Terminal on the same machine. Closing, retrying, resizing, or changing
focus must affect only that window. A window losing input focus releases its held
remote keys/buttons without ending another session. Background Mac windows keep
receiving output; application inactivity alone does not tear down connections.
Screen lock/app unlock can suppress input and protect local credentials.
App lock removes sensitive sheet contents and dismisses their nested editors;
an already presented sheet cannot retain visible saved text while locked.
Connection-setting mutations recheck app unlock when their actions execute.
Terminal mouse and wheel events require the same key-window and responder
admission as typed input, while background terminal protocol replies continue.
Terminal Copy and Find recheck unlock when invoked. Lock clears selection,
composition and embedded Find text, ends field editing and revokes the window's
responder. Each window tracks at most 256 held Kitty key reports and three mouse
buttons. Focus loss sends their matching releases once through that SSH owner,
with a 16 KiB cleanup limit inside the existing 64 KiB write budget. Cleanup can
finish while locked; it cannot admit new input or replay into a replacement shell.
The pinned frontend's synthesized movement callback is also gated at its mouse
report output, independently of AppKit's local-monitor ordering.
Optional OSC133 prompt-click cursor navigation is disabled because its delayed
callback cannot recheck the owning window's focus in the pinned frontend.
Periodic VNC status reports preserve established locked sessions; an unfinished
login still cannot complete or save credentials while locked.

Desktop retains display crops admitted by the existing Apple metadata validator,
All Displays fallback, local fit/zoom/pan, cursor, pointer, wheel and keyboard.
Desktop supports relative pointer input alongside its remote pixels, pointer,
scroll and physical keys. Resizing changes local presentation or SSH PTY
dimensions; it does not change a remote display's resolution.
VNC participates in AppKit text input: marked composition stays local, and
committed Unicode uses the shared keyboard owner. A local preedit indicator and
candidate position support input methods; losing focus discards the draft.
Actual Chinese/character-picker interaction remains a native GUI acceptance case.

New VNC logins match iPhone's retention and field validation rules. Each new
Desktop window consumes one usable saved-login attempt after unlock;
later unlocks only restore a cleared remembered password for the same account.
Cursor-only reports invalidate drawing and native cursor rectangles independently
of framebuffer changes. Save rechecks the current machine count and Pro/trial
access; existing records remain editable and a denied creation keeps its draft.
New SSH key logins recheck the displayed key against current Pro/free-key access. Terminal
uses a saved login for one initial attempt after local unlock; later cancellation,
disconnect and recovery require an explicit new-shell action. Closing a controls
sheet preserves an explicitly selected password login. Automatic key installation,
free manual setup and identity-verification recovery are available from Terminal.
Removing the preferred key with **Use Password Login** restores Password mode and
its separate account. User key creation/import checks the current shared key
count and Pro/trial access at commit, independently of each window's snapshot.
Terminal link confirmations are sheets owned by their originating window. Screen
sleep/app lock, owner closure, disconnect and surface teardown cancel them and
clear their displayed URL; a cancelled confirmation cannot open a browser later.

On macOS, **Import Key** offers **Choose from ~/.ssh…** and **Choose File…** using
a native file picker. Hidden folders and extensionless files such as
`id_ed25519` are selectable. Encrypted and unencrypted Ed25519 OpenSSH private
keys use the existing bounded importer and local Keychain library. This imports
a copy: the original file is untouched, its path is not retained, and later file
changes do not update the imported key. RSA/ECDSA, hardware-backed keys and
ssh-agent identities remain outside the supported formats. No folder is scanned
or key read without the user's explicit selection; the picker closes on lock.

## Storage and sync

Reuse `DirectMacRecordV1`, `DirectCloudVersion`, existing versioned service/account
names, bounded merge/tombstone rules and opt-in consent. Use the existing iPhone
Keychain access group for syncing metadata. A signed Mac build must be entitled
to that exact existing group; unsigned compilation is not cross-device proof.
macOS uses the data-protection Keychain for these records. Passwords, SSH private
keys, trusted host keys, saved text/actions and consent remain device-local.
Do not create a parallel iCloud key-value or CloudKit library.

## Verification

Reproducible native macOS builds, required repository validation, shared-model
regressions and existing iOS regressions precede native live verification. Verify
VNC framebuffer/input, SSH PTY output/input/resize, focus and teardown isolation,
recovery and concurrent machine/mode windows. Verify signed Mac/iPhone same-account
sync edits, conflicts, deletions, restart and offline recovery before declaring
sync complete. Synthetic servers and injected transports establish only their
covered behavior. Record signing/device and release gates separately. App Store
submission and public release are outside this goal.

## Build and development acceptance

The native entry point is `Native/Mac/MacCompanionDirectApplication.swift`.
`scripts/build_direct_macos.py` generates a development project outside the
checkout and builds only the direct Mac sources, the listed shared client
sources, and the pinned dependencies. The historical `project.yml` Mac host
composition is not this client and remains excluded. This follows the existing
iOS direct-client dependency admission workflow; it does not admit a distribution
or switch the permanent host target into a client.

The builder requires a clean LibVNCClient checkout and the checksum-pinned
OpenSSL source archive recorded in `Native/VNC/source-lock.json`:

```sh
python3 scripts/build_direct_macos.py \
  --source /absolute/path/to/pinned-libvncserver \
  --openssl-archive /absolute/path/to/openssl-3.5.8.tar.gz \
  --output /private/tmp/maccompanion-direct-macos
```

Every resolved remote Swift package must also match its admitted URL/revision and
Git source bytes/modes before and after compilation. Dirty tracked, untracked,
ignored and hidden index edits are rejected without resetting the cache. The build
report records both source-tree snapshots; a clean cache remains reusable.
The supplied LibVNCClient checkout is verified with the same actual-byte/mode
checks before and after compilation, including ignored additions and hidden
index edits. Its source-tree hashes and tracked-file counts are recorded in
`LibVNCClientSources`; a revision label alone is not accepted as provenance.

For usable macOS data protection Keychain, supply `--signing-identity` with the
existing Apple Development certificate SHA-1, `--team` and `--profile` with an
existing installed Mac development profile. The builder verifies its team,
expiration, certificate and app/group authorization, then checks the built
signature, selected certificate and exact entitlements. The existing Mac app
identity is the first, local group; the existing iPhone app group is explicitly
selected for cloud records. No profile download, app registration or release
submission occurs. Apple describes this provisioning requirement in
[TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).

Unsigned builds establish compilation and remain unsuitable for local Keychain
or signed iCloud acceptance. `build-report.json` records source/dependency hashes,
toolchain, signature facts and the separate, unverified acceptance/release flags.

`python3 scripts/verify_macos_input.py` checks native key and viewport contracts
against the manifest-indexed fixture. `python3 scripts/verify_direct_macos.py
--build /private/tmp/maccompanion-direct-macos` adds hosted Mac checks; use the
same signing arguments for local Keychain and real loopback SSH. The QA app has
its own temporary identity and excludes the iPhone group. Its missing shared
access is expected to fail visibly. These tests never certify iCloud delivery.
QA has separate DerivedData products and shares only the pinned package source
cache with the application build, so running tests cannot replace the signed
client artifact. Add `--ui` for the native window/keyboard acceptance lane, or
`--only-ui` to run that lane without hosted test-session preparation. The
temporary UI runner has an incoming-network entitlement for its loopback SSH
fixture; the client receives no server entitlement. QA stages the verified
Citadel source outside the checkout so Xcode's user scheme metadata cannot
modify the hash-pinned vendor tree.

### 2026-10-09 checkpoint

The later approved macOS simplification removes the standalone Trackpad & Keyboard
connection and its app-settings control profile. Only Desktop and Terminal appear
in the library, context menu, default picker and session routes. Old restored
Trackpad windows become Desktop windows with their original UUIDs; shared iPhone
Trackpad defaults display as Desktop on Mac. Unrelated edits preserve the shared
preference; explicitly choosing a new default writes Desktop or Terminal. Native
VNC owners always request pixels. The input-only acceptance recorded below is
historical; the shared iPhone input-only transport and its regressions remain.

The simplified client builds and signs with stable Xcode 27.0; all 171 application
source inputs match the built artifact. All 28 hosted Mac checks pass with no
skips or failures. A separate native UI check verifies the two library actions,
context menu, default picker and settings, preserves an iPhone Trackpad default
through a name edit, and opens independent Desktop/Terminal sign-in windows.
Closing Terminal preserves Desktop. Required repository validation and the
iPhone Simulator build pass. Screenshots and test results stay outside Git;
these checks do not establish live remote input or cross-device iCloud delivery.

Stable Xcode 27.0 (27A266a) builds and signs the native Apple Silicon client.
The initial signed checkpoint contains 161 application source inputs. The
existing Mac app identity, selected Apple Development certificate, and exact
Mac/local plus iPhone/cloud Keychain groups are verified. The host runs a macOS
27.2 beta; released macOS and Intel compatibility remain unverified.

The screenshot review exposed an input-only readiness bug: Trackpad suppresses
pixel presentation, while Connected previously required a presented baseline.
Its authenticated running owner now reports Connected without pixels. Desktop
still requires a complete presented baseline, including after resume or leaving
input-only mode. Twelve manifest-indexed readiness cases cover both modes,
unauthenticated owners, pause, stop and overflow. No login or wire format changes.

The library distinguishes the default mode from active sessions, lists each
connection window with its current state, and can raise an existing owner.
Each session has a compact state/service/configured-address footer. The iCloud
footer reports opt-in, refresh and errors without claiming confirmed delivery.
Connection Settings, field labels and action help clarify the controls;
Desktop fit/zoom uses one View menu, and Trackpad explains its input-only surface.
Terminal has an inset, local text-size controls and distinct Interrupt and
Disconnect actions. Text size affects only the current window and the default
for future windows; it is not a cloud preference.

Hosted Mac QA completes thirteen tests: twelve pass, one native key-window
check skips because the hosted test app cannot become active, and none fail.
Covered behavior includes registry ownership, actual Trackpad status callbacks,
native NSImage pixels and retired generations, local login/key policy, compatible
cloud records with injected offline/conflict/deletion checks, real loopback SSH
input/output/resize and independent closure. The result is
`/private/tmp/maccompanion-direct-macos/QA/Results-1791559704983605000.xcresult`.
The earlier test-session preparation stall is superseded by this completed run.
Required repository validation passes with 134 indexed fixtures.

The PR review fixes protect and dismiss native sheets on app lock, recheck
Connection Settings mutations, gate Terminal pointer events and synthesized
mouse reports, and preserve established VNC owners on locked status updates.
Hosted QA now completes sixteen tests: fifteen pass, the same native key-window
check skips, and none fail. Actual SwiftUI editor-subtree removal, all four
Terminal wheel/focus combinations, synthesized mouse movement, rejected click
focus reporting, background terminal query replies, locked Desktop/Trackpad
status reports, initial admission, late callbacks and OSC133 prompt clicks
after focus loss are covered. The result is
`/private/tmp/maccompanion-direct-macos/QA/Results-1791564878599514000.xcresult`.
The indexed native input suite now contains 31 cases, including the pinned
frontend's mouse-report formats. Nested-sheet lock/unlock appearance still
requires native GUI acceptance.

The fresh review fixes pass required stable-Xcode repository validation with
134 indexed fixtures and 59 native input contract cases. Thirteen disposable
Git-cache regressions also pass, including optimized Python; the signed build
verifies all 12 remote checkouts and 3,980 tracked files before and after building.
Its 168 source inputs and 24 artifact hashes match the report. A source-exercised
Save check covers a concurrent addition, trial expiry, locked Save, retained
draft, existing editing and recreation after removal.

The latest hosted Mac result has nineteen passes, one existing GUI-focus skip,
and no failures:
`/private/tmp/maccompanion-direct-macos/QA/Results-1791568474845953000.xcresult`.
The new real SSH checks exercise private clipboard execution, embedded field
editor dismissal, Kitty key-up/focus cleanup, mouse release, locked cleanup,
independent owners and no retired-shell replay. Saved-login tests cover missing,
unavailable, invalid and explicit fields plus one initial attempt per window.
Cursor-only SwiftUI updates verify actual overlay pixels, hotspot/position and
unchanged framebuffer content; they avoid AppKit's transient dirty flag.

The latest iPhone Simulator app build and full suite pass after the shared
Terminal lifecycle change: 174 pass, 13 optional skips, and none fail. The older
Desktop lifecycle fixture now explicitly models authentication while waiting for
fresh pixels, matching the admitted readiness contract. Actual fresh-frame and
pause/resume transport checks continue to pass.

The user authorized Xcode automation and approved system dialogs locally.
Native GUI tests authenticate Trackpad to built-in Screen Sharing and Terminal
to built-in Remote Login, checking the VM's independently known fingerprint.
Trackpad displays Connected and its input surface without remote pixels.
The current complete GUI run still fails when other windows cover its intended
owner; native focus/keyboard/closure acceptance remains pending. The opt-in
`--live-vm` lane requires explicit fixture host/account/password/fingerprint
values and captures genuine window screenshots as XCTest attachments outside
Git. It does not enable sync, use a physical iPhone, or advance VM setup dialogs.
Apple documents the separate Xcode Helper permission in its
[UI testing guide](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html).

Still required: complete GUI input/focus/closure and recovery checks, concurrent
machine acceptance, and signed same-account Mac–iPhone sync for edit/conflict/
delete/restart/offline cases. Physical iPhone use requires the fresh request in
`docs/simulator-first-testing.md` after applicable automated client checks.
Distribution dependency/signing gates and storefront configuration also remain
unverified. This checkpoint is not a completed release.

### Disposable live macOS VM

The user authorized a sample VM. A host-only Tart VM was created outside Git
under `/private/tmp/maccompanion-test-vm-20261009`, with four CPUs, 8 GiB memory
and a 1600×1000 display. It runs macOS 26.6.2 (25G83) and exposes Apple's
`com.apple.screensharing` and `com.openssh.sshd` services on ports 5900 and 22.
The native QA client authenticates directly to Screen Sharing and displays the
VM desktop; pointer clicks and synthetic keyboard text are observed in the
guest. The VM console is used only for fixture setup. No Mac Companion server,
helper or virtualizer VNC server participates in that connection.

The isolated `Experiments/NativeMacBuiltinServerQA/` SSH probe also passes against
built-in Remote Login: the independently obtained host fingerprint matches,
two concurrent authenticated connections work, closing one preserves the other,
and a real PTY accepts input, returns output and reports its requested 101×31
size. It uses the client's pinned Citadel transport and paused-read admission.
This is live transport evidence, not native Terminal window acceptance. The
probe is excluded from release targets and uses only the public VM test account;
it saves no login or trusted key in application storage.

The tool archive matches the publisher checksum and its signature verifies.
The base image is pinned to manifest
`sha256:87f3aa5ce21b5c876268f233bdfecf38b4c2a8116fe9bbb718e714cbae187377`;
every downloaded blob matches its digest. A temporary loopback cache used to
import the image was stopped afterward. VM storage, logs, result bundles and
test content remain outside Git. The VM uses no shared folders, clipboard,
audio, USB accessories, Apple ID or real user data. This fixture is useful for
live built-in-server acceptance; it does not verify Mac–iPhone iCloud delivery.

After the checks, the user requested VM disk cleanup. The VM was stopped, and
its disk, imported base-image cache, downloaded layers and temporary tools were
removed. Small manifests, setup scripts and the SSH acceptance report were
copied and verified under `/private/tmp/maccompanion-vm-evidence-20261009` before
removal. Native build/test artifacts and screenshots remain in their separate
temporary directories. Further live VM acceptance requires a recreated fixture.

### Review fixes and local key import, 2026-10-09

The latest shared iPhone suite passes 175 tests with 13 optional skips and no
failures, including password-account restoration after removing a key selection.
OpenSSH encrypted export/setup interoperability still passes. Hosted Mac QA
passes 26 tests with one existing native key-window skip and no failures. Its
seven new regressions cover the password transition, stale per-window key
libraries, extensionless/encrypted file import without modifying originals,
hidden-folder picker configuration, cancellation during picker presentation,
link-sheet background cancellation and independent window closure. Native sheet
checks inject the real lifecycle event into owned AppKit windows; they do not
constitute a physical screen-sleep or complete native input acceptance run.

Nineteen disposable Git provenance regressions cover hidden source/mode changes,
ignored additions, pinned initialized/uninitialized submodules and post-build
verification. The original modified LibVNCClient review probe is rejected. The
signed Apple Silicon build verifies actual LibVNCClient source snapshots in
addition to the twelve remote Swift package trees. Local SSH-key selection
imports a device-local copy and retains the existing Ed25519 format limits.

### Completion audit

| Requirement | Current evidence | Remaining acceptance |
| --- | --- | --- |
| Correct client baseline and preservation | Client checkpoint `ce85d33`; earlier work retained separately | None for the baseline |
| Native direct client for Desktop and Terminal | Native SwiftUI/AppKit entry point, reproducible signed build, live native VNC pixels/pointer/text, live pinned SSH PTY probe | Complete native Desktop/Terminal input and focus acceptance; reconnect/recovery |
| Feature parity and native input | Shared models and client features, 59 native input contract checks | Native keyboard/input-method, display, resize and recovery flows |
| Independent concurrent windows | UUID ownership, immutable selection, independent loopback SSH sessions, live built-in SSH connection closure isolation | Real window focus/input routing and concurrent Desktop/Terminal behavior |
| Compatible optional iCloud library | Existing schema/group/consent, injected-store merge/offline/deletion checks, verified signing groups | Same-account Mac–iPhone edit/conflict/delete/restart/offline delivery |
| Preserve iPhone behavior | 175 passed Simulator tests, 13 optional skips; latest app build passes | No additional automated regression failure is known |
| Repository validation | Required validation passes on the implementation | Repeat after any further changes |

The hosted rerun now passes with its GUI-only key-window skip. Native UI tests
execute after local system authorization, and the removed disposable VM supplied
live built-in-server evidence. Recreate the fixture to finish GUI and live server
checks, then obtain the fresh physical-device request required by
`docs/simulator-first-testing.md` for signed Mac–iPhone sync acceptance.
