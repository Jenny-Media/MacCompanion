# Controls, gestures and icon audit — 2026-10-07

## Requested changes

- App Settings → Controls opens Desktop, Terminal and Trackpad & Keyboard profiles without connecting.
- Each session uses the same per-mode quick actions. Existing per-Mac Desktop actions are retained until a shared Desktop profile is saved. Pointer speed and Follow Cursor remain per Mac.
- Pro customization is retained. Standard connection, pointer, scrolling and keyboard functions remain free. Terminal excludes Command chords, applies xterm modifiers, and sends saved text using the shell’s bracketed-paste mode when available.
- Disconnect replaces Exit to My Macs in both session menus. Cancel retains system non-destructive treatment.

## Gesture root causes and changes

The wheel handler quantized a two-finger swipe at 18 points per RFB wheel tick. This produced sparse scrolling, independent of pointer speed and local image zoom. It now uses six points per tick, capped at eight balanced ticks per update. Fractional movement is retained during a gesture; canceled, excess and ended motion is discarded, with no idle replay or deferred scroll timer. One-finger pointer movement and hold-to-drag remain unchanged. The existing press/release wheel events follow [RFB PointerEvent](https://www.rfc-editor.org/rfc/rfc6143.html#section-7.5.5).

Pinch was UIScrollView zoom of the local desktop image; it did not send a magnification gesture to macOS. Trackpad & Keyboard hides that image, so changing its local scale had no visible effect. The unused pinch recognizer is disabled in input-only mode and the guide now names this limitation. Native Mac pinch is not implemented. The user’s requested zoom target is awaiting clarification; keyboard-based application zoom would be a distinct compatibility feature.

## Symbol meaning review

| Control | Symbol | Reason |
| --- | --- | --- |
| Session category | `link` | A connected session; identical in Desktop and Terminal. |
| Connection Details | `info.circle` | Information, rather than network selection. |
| Disconnect | `xmark.circle` | Ends the connection; explicit label and destructive styling. |
| View & Display | `display.2` | Display/view choices. |
| Switch to Pointer / Trackpad | `cursorarrow` / `cursorarrow.motionlines` | Matches the destination mode. |
| Fit View | `arrow.down.right.and.arrow.up.left` | Return the image to fit, rather than expand. |
| Keyboard & Input / Extra Keys | `keyboard` | Keyboard controls; labels distinguish the two destinations. |
| Hide Keyboard / Hide Keyboard Bar | `keyboard.chevron.compact.down` | Keyboard dismissal, rather than image zoom. |
| Show Desktop | `desktopcomputer` | Matches the destination mode. |
| Right Click | `cursorarrow.click` | A click; retain “Right Click” because the symbol alone doesn’t identify a mouse button. |
| Generic shortcut | `keyboard` | Covers Control/Option/Shift shortcuts without implying Command in SSH. |
| Interrupt · Ctrl-C | `stop.circle` | Interrupt the foreground process; label distinguishes it from Disconnect. |
| Paste / Saved Text | `document.on.clipboard` / `text.quote` | Clipboard paste and explicitly stored text are different actions. |
| Appearance / Preferences | `circle.lefthalf.filled` / `slider.horizontal.3` | Color appearance and configuration. |

Other stock symbols are consistent with their labels: SSH keys/key setup, imports, copy, app settings, directional/navigation keys, password visibility, Face ID, warnings, success, cloud removal and deletion. Icon-only keyboard/visibility/floating controls retain action-specific accessibility labels. UI text remains authoritative where a glyph cannot communicate a precise action.

Apple guidance consulted: [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols). Cancellation is distinct from a destructive action; the button’s text and familiar symbol should communicate its purpose. Choosing red Disconnect is this app’s design decision because the action ends a session and may lose an unsaved shell state.

## Inventory and evidence

The audit covers the app’s SwiftUI/UIKit source in Apps/MacCompanionIOS, Native/VNC, Native/Terminal and Native/SessionActivity, including conditional symbols, recovery status symbols and quick-action mappings. Third-party terminal fonts and OS-owned keyboard glyphs are outside the app-symbol inventory.

79 distinct symbol names were checked on the stable Xcode 27.0 / iOS 27.0 Simulator. All 48 final hosted checks pass, including availability of every inventoried symbol, all three free/Pro settings views, larger-text menus, keyboard layout, observer retirement, saved custom actions and real loopback SSH input. The test verifies custom input reaches the existing authenticated PTY without reconnecting and stale custom actions cannot send after Pro access ends.

Symbols: `1.circle`, `2.circle`, `arrow.clockwise`, `arrow.down`, `arrow.down.right.and.arrow.up.left`, `arrow.down.to.line`, `arrow.left`, `arrow.right`, `arrow.right.to.line`, `arrow.triangle.2.circlepath`, `arrow.up`, `arrow.up.forward.app`, `arrow.up.to.line`, `checkmark`, `checkmark.circle`, `checkmark.circle.fill`, `checkmark.seal.fill`, `checkmark.shield`, `chevron.down`, `chevron.down.2`, `chevron.right`, `chevron.up.2`, `circle`, `circle.lefthalf.filled`, `clock`, `command`, `control`, `cursorarrow`, `cursorarrow.click`, `cursorarrow.motionlines`, `delete.left`, `delete.right`, `desktopcomputer`, `display.2`, `doc.on.doc`, `doc.text`, `document.on.clipboard`, `ellipsis`, `ellipsis.circle`, `escape`, `exclamationmark.circle`, `exclamationmark.shield`, `exclamationmark.triangle`, `eye`, `eye.slash`, `faceid`, `fn`, `gearshape`, `hand.draw`, `icloud.slash`, `info.circle`, `key`, `key.horizontal`, `key.slash`, `keyboard`, `keyboard.chevron.compact.down`, `link`, `list.bullet`, `lock.fill`, `lock.shield`, `network.badge.shield.half.filled`, `option`, `person.badge.key`, `plus`, `plus.circle.fill`, `questionmark.circle`, `rectangle.and.hand.point.up.left`, `return`, `shift`, `slider.horizontal.3`, `sparkles`, `square.and.arrow.down`, `stop.circle`, `terminal`, `text.quote`, `textformat.123`, `trash`, `xmark`, `xmark.circle`.

Evidence is outside Git:

- Source-use inventory: `/private/tmp/maccompanion-controls-icon-audit-20261007.json`
- Initial 38-test run: `/private/tmp/maccompanion-controls-gestures-20261007-pass3.xcresult`
- Initial captures: `/private/tmp/maccompanion-controls-gestures-20261007-images/`
- First validation: `/private/tmp/maccompanion-controls-gestures-20261007-validation.log`
- Final 48-test run: `/private/tmp/maccompanion-controls-gestures-20261007-accepted.xcresult`
- Final 16 synthetic attachments: `/private/tmp/maccompanion-controls-gestures-20261007-accepted-images/`
- Final required validation: `/private/tmp/maccompanion-controls-gestures-20261007-final-validation.log` (`bash scripts/validate.sh`, exit 0, 133 indexed fixtures)

The free/Pro settings and largest-text category captures were visually reviewed. Earlier test runs caught synthetic StoreKit setup and menu-animation timing mistakes; the final tests wait for verified entitlement changes and closing-panel retirement. The passing SSH test still emits NIOSSH Sendable warnings and a background-publishing warning; this audit does not establish a cause for the latter.

Physical acceptance of the new scroll sensitivity is separate; the current installed iPhone app is still build 15. Mac-app pinch behavior remains pending the user's zoom-target clarification. No upload or publication is included in this change.
