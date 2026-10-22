# Shared iOS Terminal controls

The floating menu has six entries in two rows at standard text sizes:
**Keypad · Shortcuts · Text**, then **Customize Controls · Appearance · Session**.
Session remains at the bottom right. Accessibility text sizes use a readable
vertical layout. Customize Controls opens the editor directly; there is no
intermediate Keyboard & Input submenu or duplicate header entry. Shortcuts and
Text open separate, searchable collections backed by the same preserved saved
items. Text also exposes the free Compose Text action. Opening either collection
or the editor sends nothing. Selecting a shortcut sends once; saved text opens the composer for review.
Send Text adds no Return, and multiline text still requires confirmation.

Keypad uses a grid icon and starts in the standard half-height draggable sheet.
It can expand to full height. Its searchable All Keys catalog groups Essentials,
Navigation, Function Keys, Common Shortcuts, Symbols and Numbers. Every built-in
key is available without Pro or pinning. Modifiers show Off, Next Key or On:
tap for the next key, long-press to keep on, and tap again to turn off. Each is
one compact button with explicit state; there are no separate lock icons. Hold a key to pin it without sending input. There is
no Fn or All Actions entry; saved Shortcuts and Text have their own tabs.

The keyboard bar keeps **the same configured rows** in portrait, landscape,
and with the native keyboard shown or hidden. The entire Main strip scrolls,
including the keyboard toggle and expansion control. Only the floating-menu
button stays fixed at the right. Session provides keyboard show/hide recovery. Esc, Tab,
Ctrl, Alt/Option and Shift use compact symbols. Arrows live in Navigation without duplicate Main placements; Command is optional. The real bar renderer also supplies the
input-free editor preview. Built-ins and saved placements can be reordered,
moved or removed, with draggable row handles, full visual row presets, layout-only restore and Undo. Numbers have a dedicated 1–0 row above Main by
default. The visual editor can reorder whole rows and move shared placements
between up to six total rows, including Main and Numbers. Expand Rows explicitly
shows those extra rows; 123 independently toggles Numbers. No keyboard visibility
change silently expands or collapses the layout. Legacy flat placements remain
on Main and legacy expanded values are retained without rewriting content.
Keypad hides the native keyboard while open and restores it on Done when it was
previously visible. See [row behavior and regression coverage](terminal-keyboard-rows.md).

Dragging across a key cancels button tracking so slow horizontal drags scroll
without sending that key. Holding a stationary modifier retains its lock gesture.
The Terminal composer presents over the full screen when entered from a SwiftUI
session, keeping its editor and Close/Send controls in the accessibility tree.
Typing into that local draft sends nothing until Send is explicitly requested.

Command is a remote Kitty Super modifier on iOS, enabled only when the remote
terminal application negotiates disambiguation or report-all support. It never
falls back to ordinary text, Ctrl or Alt. Saved Command shortcuts remain intact
but unavailable in legacy shells. Ending negotiated support clears armed and
locked Command. Native hardware Command copy/paste remains local, and the
macOS client's shortcut availability is unchanged.

Customization starts with two separate destinations: **Keyboard Bar** and
**Floating Menu**. Each editor previews only its destination, supports selection,
independent placement order and accessible Earlier/Later controls. Removing a
placement preserves its definition. Searchable **Shortcuts & Text** owns reusable
shortcuts/text; both editors can pin the same item without copying its payload.
Editors use a page-sized presentation, and the presenting owner closes the
sheet explicitly. Editors never send input. Cancel discards drafts; Save commits once. Changes
apply to all Macs on this device, after the sheet has dismissed. Multiline saved
text requires confirmation before input, and no saved text adds Return.
Customization retains the existing Pro requirement; standard input stays free.

## Shared settings and preservation

The new local Keychain profile applies to all Mac connections on this iPhone or
iPad. It does not introduce synchronization or change credentials, server trust,
SSH key selection, signing identities or Keychain groups.

On first load, import the existing shared Terminal quick-action profile and
every per-Mac keyboard record in the local Keychain, excluding identities owned
by the temporary-identity discard journal. Preserve action order, hidden actions,
IDs where unique, same-name entries with different contents, modifiers,
whitespace and text through the existing 4096-byte UTF-8 snippet limit.
Colliding IDs receive independent identities; neither source payload is lost.
Legacy records are retained unchanged.
Imported snippets stay in Shortcuts & Text; they are not automatically pinned into
the main menu. Existing quick-action pins and custom-row keys are retained.

The imported actions and completed-source journal are written together in one
Keychain update. Failed reads or writes leave existing records untouched.
Retries cannot duplicate a completed import, and removing an imported action
cannot resurrect it on the next load. Newly discovered legacy sources can still
be imported. Oversized or invalid data is rejected without truncation.

Save checks the stored revision to prevent one editor overwriting another or a
new import. Runtime items carry both input-epoch and controls-revision admission.
Reloading controls closes pending menus and rejects retained row buttons and
menu items. Local settings navigation remains usable without remote input
readiness. All input continues through the existing encoder and complete-action
queue admission; there is no transport-timing change or input replay.

## Verification

Coverage includes profile/migration tests, hosted UI/input tests and native
UI journeys, plus an opt-in hands-on review. Tests exercise the real
floating-menu renderer, canonical input fixtures and the production settings
sheet. The isolated QA app purchases the local StoreKit test product and
requires verified Pro access; no entitlement bypass enters the normal app.
Its live terminal connects through the production SSH client to an experimental
loopback server. Synthetic input is observed at that server, rather than inferred
from button animations. The server requests a hidden cursor to keep cursor
blinking from preventing XCTest quiescence; normal application code is unchanged.
Native rename journeys use the system Select All menu instead of assuming a
caret position, including UIKit's Next Page menu at accessibility text sizes.
Rename and search journeys wait for the software keyboard before resolving
selection presses or search-result coordinates on both phone and tablet.
Focused fields and sheets move when that keyboard appears; an early press at
accessibility text sizes can otherwise hit the keyboard prediction row.
Protocol cases mount the production native Terminal controller in a UIKit
window and observe the same session state projected by `TerminalSurface`.
This avoids introducing another SwiftUI root during the host application's
initial appearance. The native journeys retain the complete connected SwiftUI
view and settings sheets; no input/transport settling delay is added.

| Use case | Verification |
| --- | --- |
| Repeated history/cursor navigation | Native arrow taps and received SSH bytes |
| Ctrl/Alt/Shift next-key and locks | Native Keypad journey, hosted state and wire checks |
| Remote Command support | Native SSH negotiation and one-shot Command; golden vectors and clearing on mode exit |
| Stable bar and compact sheet | Native keyboard show/hide, half-sheet drag to full height, grouped key sends and menu alignment |
| Interrupt with keyboard hidden | Native Keypad Ctrl-C and received byte |
| Occasional function/navigation keys | Native F1/Home/End, canonical key vectors |
| Numbers and more terminal space | Independent number row, explicit expansion, scrolling keyboard controls, a fixed menu and All Keys |
| Reusable Unicode/path/multiline text | Search, exact SSH bytes, cancel/confirm, no added Return |
| Create a shortcut | Name/key editing and final chord preview; explicit deletion |
| Many saved items and favorite placement | Search over 43 saved texts; reuse and unpin preserve one definition |
| Independent keyboard/menu customization | Separate native destinations; independent order model tests |
| Large text and accessible reordering | Native accessibility XXXL journeys and actual menu renderer move actions |
| Hardware/moved keyboard geometry | Hosted keyboard-guide and composer layout checks |
| Settings shared across Macs | One profile, multiple legacy Mac imports and revision checks |
| Connected Save/background/reconnect | Native Save then real SSH input, suspend/retained-panel admission and loopback integration |

A Save notification is deferred in the editing session until its settings sheet
finishes dismissing. Other sessions reload immediately. The editor no longer
invokes a second synchronous reload. Native navigation keeps Back separate from editable content; toolbar actions
belong only to the active destination. The bar retains its configured rows across keyboard and composer transitions.
Frame regressions check scrolling keyboard placement and a fixed floating anchor, symbol hit areas, reachable
custom keys, explicit row heights and stable layout across keyboard focus changes at narrow phone and tablet widths.
Each Keypad presentation has independent
state; reopening it cannot revive a retained callback from an earlier panel.
Saved-item search uses an inline field and full-width row hit areas, without an
additional search-controller presentation between selecting an item and closing
the panel.

After the managed Simulator build, run the focused regressions with:

```sh
python3 scripts/verify_terminal_pro_simulator.py --build /path/to/simulator-build \
  --simulator SIMULATOR_UUID --test-diagnostics never \
  --only-testing DirectClientTests/TerminalControlsProfileTests \
  --only-testing DirectClientTests/TerminalControlsUITests
python3 scripts/verify_terminal_pro_simulator.py --build /path/to/simulator-build \
  --simulator SIMULATOR_UUID --test-diagnostics never --terminal-controls-ui
bash scripts/validate.sh
```

The broader selection also covers keyboard feedback, real loopback SSH input,
quick-action editing, Terminal layouts, text sizing and composer layout. The
native runtime journey rotates with the software keyboard visible and requires
usable terminal height and restoration on return to portrait. On iPad, hosted
coverage uses `testComposerReservesTheShortcutBarAcrossKeyboardLayouts`, which checks
docked, moved and hardware keyboards with tablet window sizes. An additional
iPad attempt with the phone rotation check failed because a hosted scene
geometry request left its window portrait; that failure is retained, and is not
reported as tablet rotation acceptance.

Simulator and repository-validation results are recorded in the PR. Synthetic
screenshots, failed attempts, logs and xcresult bundles remain outside Git under
`/private/tmp/maccompanion-terminal-redesign-20261020/` and
`/private/tmp/maccompanion-terminal-ux-20261020/`.

For hands-on review, add `--terminal-controls-review` and select
`TerminalControlsJourneyTests/TerminalControlsJourneyTests/testInteractiveReview`.
The QA-only Finish Review button ends the bounded review without changing Pro
entitlement policy. Physical VoiceOver, hardware-keyboard behavior, dictation
and the reported device-only Save symptom still require physical acceptance;
Simulator results do not certify those.
