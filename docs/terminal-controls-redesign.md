# Terminal controls redesign

## Interaction contract

The controls overview is navigation, without a global Save transaction. Keyboard
Bar and Floating Menu open separate full-screen destination editors. Each editor
owns a value draft: Done commits once, Cancel discards all changes, and Undo
reverts placement changes. Nested saved-item edits use Save and belong to that
same draft. Edits opened directly from Shortcuts or Saved Text use Save independently.
Persistence retains optimistic revision admission and reports failed saves without
closing the draft.

Keyboard and Menu Favorites use the approved layout-first clickable prototype.
Keyboard editing opens the continuous production bar, with drag-only row handles
and a per-row menu in the former Add-button slot. Add Key is first, followed by
Alignment, Visibility and Remove Row. The required main row stays visible and
the last row offers Clear Row. Add Row opens complete templates; key taps open
focused actions, replacement or creation. There is no standing catalog, selection toolbar,
terminal backdrop or disabled Undo control. Options opens a separate read-only
preview with the native keyboard. Its UIKit controller owns first-responder
transitions. Customization never sends SSH input, and the runtime keyboard is restored
only in the same session.

Row handles reorder on a direct pan. Whole-row lift, source dimming, an insertion
line and edge autoscroll remain available. Keys use explicitly enabled UIKit drag
interactions. Focused actions supply tap alternatives for every movement. Add Row
explains transfer of existing keys before assembling a complete template without
duplicates. Rows left empty by transfer are removed, except the required main row.
Removing the main row promotes another; removing the last row clears it. The
six-row limit is explained when an addition cannot proceed.

Add pickers separate Keys, Shortcuts and Text, with app Actions available when
adding a menu favorite. Custom definitions and tool presets
can be created inside either editor. Both surfaces reference one saved identity.
Removing a placement retains its definition. Save in a nested item editor changes
only the local layout draft; Done commits once. Cancel confirms discarding a changed
draft. Undo appears after a change and also reverses restores and removals.
Unavailable customization shows a recovery/access explanation instead of a grayed
out editor. Invalid content produces an explanation when Save is requested.

Menu Favorites displays only editable favorites and Add Favorite. Its optional
full-menu preview shows fixed destinations as passive labels in runtime order:
Keypad / Shortcuts / Text, then Customize Controls / Appearance / Session. It
contains no disabled navigation buttons or unrelated keyboard bar. The saved-text
form shows its name, text, insertion behavior and shared-edit explanation without
permanent placement lists or technical counters.

Runtime All Keys contains keys, search, modifiers and explicit pin actions. It
uses native medium/large detents. Shortcuts and Text have separate runtime entry
points. A shortcut row sends once; a text row opens a temporary review draft.
Runtime text review preserves existing no-extra-Return, multiline/tab confirmation,
draft retention and lifecycle admission. Manage opens the canonical saved library.

## Tool presets

Tool Presets is a multi-select catalog. Adding a preset twice reuses its saved
identity, including after editing its name or chord. Presets are optional and
can be edited and placed like custom items. No tool detection or remote config
change occurs. Prefix commands remain separate taps; no sequence execution is
introduced. The prerequisite is retained on the saved definition and displayed
in the preset picker, editor, library and runtime browser.

Sources checked on 2026-10-21:

- [tmux Getting Started](https://github.com/tmux/tmux/wiki/Getting-Started)
- [Zellij preset guide](https://zellij.dev/documentation/keybinding-presets)
- [Zellij default binding example](https://github.com/zellij-org/zellij/blob/main/example/config.kdl)
- [Herdr current keymap](https://github.com/herdrdev/herdr/blob/master/docs/next/website/src/content/docs/keyboard.mdx)
- [Herdr current default configuration](https://github.com/herdrdev/herdr/blob/master/src/main.rs)

Herdr's current defaults differ from older indexed README copies. New workspace
uses prefix then Shift+N; rename workspace uses Shift+W; zoom uses Z. The picker
links to the current keymap and explains that custom remote bindings may differ.

## Verification scope

Regression and QA sources accompany the redesign, including preset validity,
identity, placement, cancellation, input admission and synthetic SSH coverage.
They were not rerun for the final physical-device polish. Several existing QA
cases still refer to retired number-toggle APIs, row renaming, the combined
library and the previous keyboard-preview toggle. Updating those cases, adding
alignment/docked-preview coverage and running the managed validation and
Simulator journeys remain pre-merge work. Earlier PR test results do not certify
this revision.

Simulator screenshots contain synthetic QA data and stay outside the repository.
Simulator acceptance is distinct from physical-device or real-tool acceptance.
No SSH/security protocol behavior changes are introduced.

## Physical-device polish pass

Favorites have balanced interior padding. Full Menu Preview uses the production
popup renderer, header, two-column favorites and six navigation entries as a
passive preview. Add Favorite includes standard Actions as well as keys,
shortcuts and text, so individual actions can always be restored.

The app-action catalog contains Compose Text, Paste, Copy Selection, Show/Hide
Keyboard and Expand/Collapse Rows. Escape, Tab and Return live under Keys;
common Ctrl combinations live under Shortcuts in the placement picker. Existing
favorites keep their IDs, titles and placements when older built-in aliases are
converted to key/shortcut definitions. Restoring favorites reuses definitions by
operation or chord. Runtime keyboard/row action labels reflect their current
state, and state-change feedback is emitted once by the owning control.

Keyboard editing hides the live session button's anchor and removes its width
constraint. There is one trailing row menu per row, with no non-interactive
floating-button stand-in. The real terminal overlay keeps its anchor and button.

Numbers is an ordinary row preset with the same visibility, ordering and editing
as other rows. The dedicated number toggle and session preference are retired;
a one-time compatibility conversion preserves old row visibility and removes
only retired toggle placements. Other saved placements remain unchanged.

Shortcuts and Saved Text have separate search/create/manage screens. Native
reorder handles affect library order only. Tap or swipe right to edit, swipe
left to reveal Delete; deletion identifies affected layout placements. The
named tmux, Zellij and Herdr entries also support direct placement without
creating an item in the library first. Done/Save/Add use the prominent accent
style, while Cancel/Close remain neutral. Key pickers use compact, rectangular
keycaps with one-line labels and adaptive columns.

Regression tests and Simulator walkthroughs are deferred for this pass at the
user's request; the immediate acceptance lane is a physical iPhone install.

Modifier controls use matching symbols in Add to Row, the keyboard bar and All
Keys. The armed state uses an opaque deep-blue fill, white symbol and outline;
the held state adds a short underline without changing key dimensions. State
text remains available to VoiceOver without occupying the keycap. The palette
adapts to light, dark and increased-contrast appearances. Row actions now live in
the trailing native menu. Names are automatic: preset names or numbered Custom
Rows identify menus, placement descriptions and accessibility labels. Visibility
is selected directly in a submenu, and removal retains confirmation and Undo. The
left handle only reorders, with accessible Move Row alternatives. Promoting a
hidden row to the required main row makes it visible so controls remain reachable.

Keycaps now share a 44-point minimum width and the same scaled text/symbol size
in the live bar, row templates and editor. Digits are never compressed to fit a
row; long rows scroll horizontally. Each row's menu offers Left, Center, Right
and Fill alignment. Fill shares spare width equally without shrinking keycaps;
the other choices position a fitting row within its available width. Existing
Numbers presets default to Fill and other rows default to Left. Alignment is
stored on the row and participates in the editor's draft, Cancel and Undo.

Preview with Keyboard opens a separate read-only screen using the production
bar as a UIKit input accessory directly above the system keyboard. It contains
no editing handles, row menus, Add Row footer or Undo notice. Expanding rows is
local to the preview; closing restores the unchanged editor draft. The preview
has no terminal/session reference, discards keyboard input and cannot send to a
Mac. The main row reserves the live session button's space without adding a
second floating button to the editor.

On 2026-10-22, the managed normal iPhone build completed and all 631 recorded
production source input hashes matched the working tree. Development build 133
was signed, installed and launched on the user's iPhone 18 Pro Max; its installed
version and visible Keyboard Bar editor were verified. The user subsequently
reported that it works well. This records physical acceptance feedback for that
build, without claiming a completed automated suite or exhaustive device matrix.
Signing material and screenshot evidence remain outside Git.
