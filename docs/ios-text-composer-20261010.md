# iOS session text composer

Issue: [Native text composer](https://github.com/Jenny-Media/MacCompanion/issues/7).

Desktop, Trackpad & Keyboard and Terminal now expose **Compose Text** under
**Keyboard & Input**. This free iOS tool uses a native multiline editor with
selection, composition and explicit Paste. Editing sends no remote input.
**Back to Session** keeps the draft so the user can choose remote focus; reopening
the composer returns to that draft. **Discard** asks before clearing it.

The only delivery action is **Send Text**. Spaces, tabs and trailing line breaks
are preserved. CRLF, CR and Unicode line separators become LF. A draft containing
line breaks or tabs requires confirmation, including an explicit warning when it
ends with a line break. No extra Return is appended.

- Desktop and Trackpad type Unicode key events into the currently focused Mac
  app. A line break presses Return; a tab presses Tab. These can submit content,
  run commands or change focus.
- Terminal writes UTF-8 to the current SSH PTY. It reads the program's current
  bracketed-paste mode at delivery time. Without that mode, embedded line breaks
  can run commands. Selecting Send Text does not prevent command execution.

The editable draft is bounded to 16 KiB UTF-8. An oversized paste is rejected as
a whole. A Desktop send is limited to 256 Unicode scalars by its balanced
512-event queue; a Terminal send is limited to 4096 UTF-8 bytes before optional
paste framing. Other C0/C1 controls are rejected. Oversized sendable content stays
editable and is never silently truncated.

Each draft belongs to one viewer or PTY generation. Background, app lock,
connection replacement, mode change and session end clear it. There is no storage,
sync, clipboard monitoring, diagnostic content or automatic input replay. Once a
send is admitted, editing, dismissal and duplicate sends are disabled until the
local write completes. Queue rejection keeps the draft. Interrupted writes report
uncertain delivery on the composer or session screen and require a deliberate
next action. Local completion does not acknowledge remote app consumption.

Every composed VNC event carries its group's identity. Pause, mode change, Stop
and connection end retire that identity under the input queue lock, including
events already copied by a worker blocked in a write. Only a write already
admitted can finish; the worker drops the remainder and releases any held key
before sending a newly admitted group. Automatic reconnection preserves the
interrupted-send warning until the user selects Continue.

The specification and manifest-indexed `ios-text-composer-v1.json` define the
encoding and confirmation cases. Native QA covers all three entry points,
balanced VNC packets, PTY bytes, draft retirement and explicit confirmation.
macOS UI and the legacy Observe/Act/Control protocol are unchanged.

## Verification

- Stable Xcode 27.0 (27A266a): native iOS build passes; recorded hashes match all
  590 current source inputs.
- `bash scripts/validate.sh`: passes. All 135 manifest-indexed fixtures and the
  native appearance boundary also pass their final checks.
- Focused composer checks: 12 passed, zero failures or skips. Includes all three
  native entry points, marked-text editing, oversized editor input, app lock with
  a hidden draft, balanced VNC socket packets and actual SSH PTY bytes. Both new
  regression tests failed before the recovery fixes and passed afterward: a
  stalled copied group cannot continue across Trackpad pause/resume, its held key
  is released before fresh text, and the warning survives automatic replacement
  in Desktop and Trackpad until acknowledgement.
- Broader VNC frame, session-control, lifecycle and recovery checks: 46 passed,
  zero failures or skips, using the final recovery fixes.
- The initial implementation's full native suite on the isolated Simulator:
  226 tests, 13 optional tests
  skipped, one existing cloud-sync read-count assertion failed. That test passed
  in isolation; the full run is not recorded as wholly green. StoreKit/Pro cases
  also pass after the fresh Simulator's test configuration initialized.
- OpenSSH export and sandboxed key-setup interoperability checks pass.

The shared QA Simulator had another QA app active and interrupted test processes.
Final checks used the temporary **Mac Companion Composer QA** Simulator
(`29EA219C-C71E-45A5-91F7-4337C0151753`, iPhone 18 Pro Max, iOS 27.0). Captures
and generated build/test artifacts remain outside the checkout.

Physical acceptance still needs an iPhone/iPad connected to built-in macOS Screen
Sharing and Remote Login: native IME and dictation, explicit Paste, Unicode and
emoji in a remote text editor, desktop Return/Tab behavior, and multiline shell
input with bracketed paste enabled and disabled. Simulator and synthetic socket
checks do not establish those hardware results.

## Compact composer revision (historical, 2026-10-13)

Compose Text is a built-in Quick Action in Desktop, Trackpad and Terminal.
Untouched older default rows gain the action while retaining their existing
identifiers; customized rows are preserved. The composer appears as a compact
panel above the actual keyboard, leaving the desktop visible. Back returns to
the destination without losing the draft; Expand provides more editing space.
Send remains outside scrolling content, including at large accessibility sizes.
Short landscape layouts use accessible Back, Discard and Send controls beside
the scrollable editor; destination context and validation explanations stay accessible.
Return/Tab confirmation, explicit delivery, size limits and generation/readiness
fences remain in place. Background/lock cancellation clears the draft and
dismisses even when it arrives during the presentation transition.

Temporary inactive gestures do not present a lock cover. Real backgrounding
retains the privacy mask. A valid grace return prepares visible presentation
before becoming active without admitting inactive input; current successful
authentication keeps a quiet opaque transition until current active admission;
then the main interface, controls and unlocked publication become available together.
Retained Desktop recovery keeps cached pixels at normal opacity, checks for a
fresh frame silently, and shows delayed Updating desktop feedback after one
second. Actual connection replacement alone uses Reconnecting. iOS can suspend
a background app; these changes do not promise unlimited background networking.

Simulator coverage exercises these policies with native windows and the keyboard
layout guide, actual rendered Send geometry, current/canceled authentication
callbacks, native editor input and existing VNC/Terminal lifecycle fences.
Physical Face ID and third-party keyboard acceptance remain separate checks.


## Maps-style resizing revision (2026-10-13)

The keyboard-aware panel now has a grabber with compact and expanded snap
positions. Dragging keeps the same native editor mounted, preserving the draft,
selection and keyboard focus. Expand/Collapse also provides an accessible action.
Editor scrolling leaves the panel size unchanged. A short canceled closing drag
retains the draft; a completed swipe closes it while retaining unsent text.
Sending prevents swipe dismissal. Background and lock still retire the draft.

The panel uses public UIKit gestures and the actual keyboard guide. Native
UISheetPresentationController prototypes expanded automatically with the
keyboard and dismissed it during resizing, so they failed the required typing
experience. The snapping panel preserves the verified keyboard-aware layout.
Simulator UI tests use real grabber drags, editor scrolling, typing, dismissal
and background transitions; native editor tests cover selection, short landscape
and accessibility sizes. Physical iPhone acceptance remains a separate check.


From the checkout, reproduce the drag suite after a normal simulator development
build. Use the same `DEVELOPER_DIR` for the builder and these commands. The build
output is saved evidence; the leased compiler workspace contains the QA project,
intermediates and package checkouts. Choose a new result-bundle path for each run.

```bash
python3 scripts/verify_terminal_pro_simulator.py --build /absolute/build-output --simulator SIMULATOR_ID --generate-only --composer-ui
python3 - /absolute/build-output SIMULATOR_ID /absolute/composer-results.xcresult <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path.cwd()
sys.path.insert(0, str(root / 'scripts'))
from build_cache import compiler_workspace

with compiler_workspace(Path(sys.argv[1]), root) as compiler:
    subprocess.run([
        'xcodebuild', '-project', str(compiler / 'QA/DirectClientQA.xcodeproj'),
        '-scheme', 'ComposerSheetQA',
        '-destination', 'platform=iOS Simulator,id=' + sys.argv[2],
        '-derivedDataPath', str(compiler / 'DerivedData'),
        '-clonedSourcePackagesDirPath', str(compiler / 'DerivedData/SourcePackages'),
        '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation',
        '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
        '-resultBundlePath', sys.argv[3], 'test'
    ], cwd=root, check=True)
PY
```

The generated QA app links the experiment entry point only in its private
target. Release and normal development targets do not link experiment sources.

## Floating composer revision (historical, 2026-10-13)

The default presentation is now a compact floating panel inside the session.
Drag the grabber to move it; release near an edge to snap. The panel stays within
the safe area above the actual keyboard, and relative placement follows rotation
and keyboard changes. Undocked and floating tablet keyboards are tracked; near
the top edge the panel uses readable space below or beside the keyboard.
VoiceOver exposes movement actions on the grabber. Narrow compact windows group
Discard, Expand and Dock in Composer actions, leaving Back, error details and
Send directly reachable.

Expand fills the available area; Collapse restores the compact panel. Dock
attaches it near the keyboard with the existing Maps-style height snaps. Undock
restores its floating position. All presentations share one mounted native editor,
preserving draft, selection and typing focus. Back still retains the draft for
choosing a remote destination. Background, lock and session replacement retire it.
Sending blocks movement and presentation changes; late gestures from retired
presentations cannot affect a new editor. Only Send Text delivers input, with the
existing confirmation and readiness checks.

Simulator coverage includes real grabber drags, edge snapping, docking,
expansion, editor scrolling, rotation, actual keyboard geometry, retained selection,
Dynamic Type and lifecycle cancellation. Tablet safe-area/keyboard geometry is
covered by controlled native rendering on an iPad Simulator in portrait and
landscape, including moved floating and full-width keyboard viewports. Actual iPad
system-keyboard floating/undocking gestures remain a final hardware check, as
explicitly agreed after the simulator could not enter those modes. Physical
dictation and IME acceptance remain separate. Cursor and password-manager
investigations stay paused.

## Text bubble and persistent Unlock card (2026-10-13)

The current composer is a smaller floating text bubble with a grabber, Close and
circular arrow Send. The title, destination/presentation toolbar, Expand/Collapse,
Dock/Undock and Discard controls are removed. Close keeps the draft; long text
scrolls in the same native editor. Destination context is available to accessibility,
and conditional validation/delivery-error details remain reachable. Drag/snapping,
keyboard/orientation tracking, explicit confirmation and lifecycle fences remain.
Close and Send have 44-point hit regions. Dynamic Type grows the editor within
keyboard-safe bounds. Compatibility transitions remain internal and have no UI
entry or grabber-tap action.

Unlock uses one persistent card through authentication and active admission.
Unlocking indicates evaluation; Opening indicates success awaiting activation.
Both states disable the button. Failure/cancellation exposes an explicit Unlock
retry only while foreground and protected data permit it. Current successful
authentication plus active admission still reveal the main UI and enable controls
together. The separate Mac Companion-only transition is removed.

## Restrained Liquid Glass (2026-10-14)

The floating bubble uses one native regular Liquid Glass outer surface. Editable
text has a stable secondary system background; Close stays quiet and Send remains
the single accent action. The native material keeps accessibility adaptations,
with a system-material fallback where Liquid Glass is unavailable. No additional
glass layers or controls are added. Drag, snapping, keyboard/selection retention,
confirmation, delivery and background/lock retirement are unchanged.
