# Terminal keyboard rows and All Keys

Terminal controls are shared across all Macs on this device. Showing, hiding or
rotating the native keyboard keeps the configured rows and their contents.

## Rows and scrolling

The default main row is Keyboard, Expand, Esc, Tab, Ctrl, Option, Shift and
← ↓ ↑ →. Expand is second, immediately after Keyboard, and disappears when
there are no nonhidden rows set to When Expanded. Only the floating menu stays
fixed; every key in each row can scroll horizontally. The default main row uses
Fill alignment. Numbers is a separate ordinary 1–0 row above it. Navigation
includes all four arrows plus Home, End, PgUp and PgDn and starts collapsed.
Command is optional and requires negotiated remote-application support.

Rows are identified by their actual preview and their current position: Row 1,
Row 2, etc. Reordering changes the displayed number, preserving identity and
configuration. Numbers, Navigation and other preset names identify templates in
Add Row; editing a row never leaves a misleading permanent name.

Each trailing row menu offers Add Key, visibility (except the always-visible
main row), alignment, Scroll Start and removal. Drag handles only reorder rows.
Alignment positions fitting contents using Left, Center, Right or Fill. Scroll
Start independently chooses Automatic, Left or Right for overflowing contents.
Automatic starts right-aligned rows at their right edge and others at their left.
The initial preference applies when opening a session or preview, or changing
the preference. Manual scrolling survives typing, modifiers, keyboard show/hide
and ordinary updates. Resizing keeps a visible right edge at the right edge;
otherwise it preserves the offset within the new bounds.

Up to six rows are configurable. Add Row offers full previews of Numbers,
Essentials, Navigation, Function Keys, Symbols, Shell Shortcuts and Blank. A
preset always adds its complete contents without moving or deleting existing
placements. Add always creates another placement, including intentional copies
in the same row or menu. Drag moves the exact copy; remove removes that copy.
Undo restores the previous draft. Removing the final row clears it so the editor
remains usable. Restoring layouts keeps saved definitions and menu favorites.

Keyboard shortcut keycaps show the exact character or chord, such as ⌃b, c, %,
N or ⌃p. Pickers, editing details and accessibility retain descriptive names,
tool identity, chord and any After Prefix prerequisite. Tool commands send one
key or chord each; they do not automatically send the prefix or a sequence.
Prefix-dependent commands remain optional in the picker’s After Prefix section.
Saved text retains its name. Repeated saved placements share one editable
shortcut/text definition and have independent ordering/removal identities.

## Editors, keypad and saved items

The keyboard editor uses the real bar renderer without an input owner. Tap a
key to edit; drag keys within or between rows and handles to reorder rows.
Preview with Keyboard opens a separate read-only screen with the production bar
attached directly to the system keyboard. It has no editor chrome or input
execution and closing it leaves the draft unchanged.

The floating-menu editor uses the production panel renderer. Favorites and
fixed navigation match the real popup. Actions, Keys, Shortcuts and Text can be
added directly. Shortcuts and Saved Text also have separate searchable libraries
with native reorder, swipe-right edit and swipe-left delete. tmux, Zellij and
Herdr presets can be placed directly while configuring either layout.

Keypad opens All Keys at the native medium sheet height; drag the grabber to
expand. Every built-in key is usable without customization or Pro. Compact
keycaps preserve 44-point touch targets, with adaptive layouts at larger text
sizes. Tap sends once and leaves the sheet open. A modifier tap arms the next
key; long-press keeps it on; tapping again turns it off. Opaque accent fill and
outline indicate active state and an underline indicates held state. VoiceOver
announces the state. Saved text opens Compose Text for review; explicit Send
Text adds no Return, and multiline text requires confirmation.

## Regression coverage

TerminalControlsProfileTests and TerminalControlsRedesignTests cover legacy
migration, shared definitions, independent repeated placements, full preset
additions, exact-copy removal/move/replace, Undo, ordinal row names, scroll-start
persistence, validation, optimistic saves and write failures.
TerminalControlsUITests exercises actual UIKit geometry, independent utility
buttons, exact-copy callbacks, compact labels, scroll preservation, docked
preview, negotiated Command and stale-input rejection. Native journeys in
Experiments/TerminalControlsQA drive add/edit/reorder/remove, Save/Cancel, Undo,
keyboard preview, tool presets and runtime input against synthetic data. The
harness is not linked into release targets. Screenshots and result bundles stay
outside Git. Encoding fixtures remain indexed solely by spec/fixtures/manifest.json.
