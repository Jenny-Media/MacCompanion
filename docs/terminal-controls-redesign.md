# Shared iOS Terminal controls

The floating Terminal menu exposes **More Keys**, **Saved Text**, **All Actions**
and **Customize**. More Keys includes navigation and function keys, modifier
locks, clipboard actions, and the existing Ctrl-C/Ctrl-D/Ctrl-Z shortcuts.
The compact software-keyboard row keeps Esc, Tab, Ctrl and Alt beside the fixed
keyboard toggle and floating-menu button. The optional number and custom rows
remain available. There is no Fn button or separate iOS snippet editor.

**Terminal Controls** previews the custom row and the actual floating-menu
renderer. Tap an action to edit it, drag to reorder, or use Earlier/Later.
Each key, shortcut or saved-text action has one definition, with independent
keyboard-row and menu placements. Unpinned actions remain in the library.
Draft edits never acquire a session input callback. Cancel discards the draft;
one Save commits it. Customization retains the existing Pro requirement.
Free standard keys and Compose Text remain available.

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
Imported snippets stay under Saved Text; they are not automatically pinned into
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

The new coverage consists of 11 profile/migration tests, four hosted UI/input
tests, and one native Save/Cancel journey. The hosted tests use the actual menu
renderer and canonical terminal encoding/paste fixtures. The journey presents
the production settings sheet over an in-memory store, purchases the local
StoreKit test product, requires verified Pro access, and checks zero writes on
Cancel and one write on Save. Its app and signing metadata are generated only
for Simulator QA; no entitlement bypass enters the normal app.

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
quick-action editing, Terminal layouts, text sizing and composer layout. On
iPhone it uses the native composer rotation/row-restoration check. On iPad it
uses `testComposerReservesTheShortcutBarAcrossKeyboardLayouts`, which checks
docked, moved and hardware keyboards with tablet window sizes. An additional
iPad attempt with the phone rotation check failed because a hosted scene
geometry request left its window portrait; that failure is retained, and is not
reported as tablet rotation acceptance.

Simulator and repository-validation results are recorded in the PR. Synthetic
screenshots, failed attempts, logs and xcresult bundles remain outside Git under
`/private/tmp/maccompanion-terminal-redesign-20261020/`.
