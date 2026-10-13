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

## Compact composer revision (2026-10-13)

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
authentication hides the cover immediately and publishes unlock when active.
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


Reproduce the drag suite after a normal simulator development build:

    python3 scripts/verify_terminal_pro_simulator.py --build /absolute/build-output --simulator SIMULATOR_ID --generate-only --composer-ui
    xcodebuild -project /absolute/build-output/QA/DirectClientQA.xcodeproj -scheme ComposerSheetQA -destination 'platform=iOS Simulator,id=SIMULATOR_ID' -derivedDataPath /absolute/build-output/DerivedData -parallel-testing-enabled NO test

The generated QA app links the experiment entry point only in its private
target. Release and normal development targets do not link experiment sources.
