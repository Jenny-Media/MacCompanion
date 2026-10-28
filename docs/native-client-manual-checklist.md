# Native client manual acceptance checklist

Saved 2026-10-10 for macOS TestFlight **1.0 (27)**, built from `0deac29`.
Use an Apple silicon Mac running macOS 26 or later. Run the iOS regression
checks with an iOS build containing the same client changes. This is a pending
manual checklist; automated validation and TestFlight availability do not mark
these items complete. Record app/build, OS, device, result and date when testing.
Items 1–5 have the highest priority.

## 1. Sign-in and password managers

- [ ] Fill credentials with Apple Passwords and 1Password. Filled values register immediately.
- [ ] Try an incorrect password, Cancel, then reconnect. Errors are clear and recovery works.
- [ ] Check the dialog with the password-manager popup and narrow windows. Fields and actions remain visible and stable.

## 2. SSH keys from disk

- [ ] Select an Ed25519 OpenSSH key from `~/.ssh` and another folder without importing a private-key copy.
- [ ] Connect with unencrypted and encrypted keys. Encrypted keys request a passphrase for each connection.
- [ ] Quit, reopen and reconnect. The original file remains accessible through its device-local bookmark.
- [ ] Try a wrong passphrase and a moved, deleted or replaced file. Recovery is clear; stale access or a changed identity requires explicit reselection.
- [ ] Switch keys between independent windows. The displayed key and authentication identity agree.

## 3. Multiple independent windows

- [ ] Open Desktop and Terminal sessions to two Macs, including both modes on one Mac.
- [ ] Switch focus, resize windows and close one session. Only the focused session receives input; other connections continue.
- [ ] Hold a modifier or mouse button while changing focus. The previous session receives the matching release.

## 4. Desktop input and fullscreen

- [ ] Test clicking, dragging, right-clicking, scrolling and shortcuts using direct pointer control.
- [ ] Test Chinese/Japanese input and focus changes during composition. Draft composition stays local and committed text reaches the remote Mac.
- [ ] Enter and leave fullscreen. Connected chrome is reduced and session controls remain reachable.
- [ ] Test fit, zoom and display selection. The selected display stays reachable and pointer coordinates remain correct.

## 5. Signed Mac–iPhone iCloud sync

- [ ] Use signed builds on the same iCloud account with sync enabled on both devices.
- [ ] Create, edit and delete saved Macs on each device. Both libraries converge.
- [ ] Make conflicting edits offline, reconnect and restart both apps. Changes recover consistently and deleted entries do not reappear.
- [ ] Verify credentials, private keys, disk-key references, saved text and server trust remain device-local.

## 6. Connection addresses

- [ ] Add, remove and reorder local and private-VPN addresses. Order and values persist.
- [ ] Make the first address unreachable. Fallback follows the configured order before authentication.
- [ ] Enter invalid or duplicate addresses and invalid ports. Validation is clear and the draft is retained.

## 7. Nearby discovery

- [ ] Refresh the nearby list. Duplicate services consolidate and device icons are useful.
- [ ] Select a nearby card. The appropriate address populates the connection editor.

## 8. Default connection action

- [ ] Double-click a saved Mac and press Return. Both use the selected default mode.
- [ ] Change the default between Desktop and Terminal, restart and repeat. The choice persists.

## 9. Terminal recovery

- [ ] Test typing, paste, IME and resizing. Input and PTY dimensions remain correct.
- [ ] Sleep/wake and interrupt the network. Recovery is clear and input works after opening a replacement shell.

## 10. Desktop controls and setup guide

- [ ] Check grouping, spacing, labels, scrolling and narrow-window layouts.
- [ ] Read the setup guide on macOS and iOS. Instructions are readable and all controls are visible.
- [ ] Open quick-action customization in each supported mode. iOS previews the session grid; Mac previews the native menu rows. Selecting a preview action edits it inline without sending input to the remote Mac.
- [ ] Drag actions and use Move Earlier/Later with VoiceOver. The preview, saved order and reopened session menu agree.
- [ ] Add, rename, edit and remove a shortcut or saved text. Add Action shows only standards that aren't already visible; hidden actions can be restored. Limits disable additions without producing an empty menu. Save keeps the draft and Cancel discards it.
- [ ] Restore Defaults requires confirmation. Verify Pro-expired and unreadable-storage states remain safe and actionable.

## 11. Settings and error states

- [ ] The library gear opens Settings directly. Set Up Your Mac is reachable in Help.
- [ ] Navigate Appearance, Controls, SSH Keys, Sync & Security, and Help on both platforms. Key sources and Back/Done actions are clear.
- [ ] Change Light, Dark and System while Appearance is open. The existing sheet updates immediately without losing its navigation; nested sheets follow the same choice.
- [ ] Add a new Mac. Addresses appear first, a pristine draft has no validation warning, and ports/details remain discoverable in disclosures.
- [ ] Expand Connection Details before sign-in. Addresses and service ports match the configuration; error details refresh without another modal.
- [ ] Open Pro while the store is unavailable. Benefits stay visible, there is one store retry, and free features remain accessible.
- [ ] Expand What syncs and Manage Sync, including with sync disabled. Review the complete enable/removal disclosures without confirming a removal unless intended.
- [ ] Try unavailable hosts and disabled Screen Sharing/Remote Login. Errors explain the next step and Retry/Cancel work.
- [ ] On first SSH connection, check the identity prompt. A changed server identity requires explicit verification.

## 12. iOS regression

- [ ] Verify Desktop, Trackpad & Keyboard and Terminal in an iOS build containing these changes.
- [ ] Verify existing touch controls, keyboard modes, keyboard avoidance and mode-specific preferences remain available.
- [ ] Check first-tap mode selection, reconnect and cancel. The selected mode opens consistently.

## Result record

| Item | App/build | OS/device | Result | Date/notes |
| --- | --- | --- | --- | --- |
| 1–12 | | | Pending | |

Keep feedback free of passwords, private keys, private addresses and sensitive
screen content. Store screenshots outside Git, as required by `AGENTS.md`.

## Settings feedback follow-up

- Expand Mac Details in Edit Mac: name, type and Refresh Details form a compact group with no blank area. Check a detected laptop and an unknown model.
- Expand Service Ports in Add Mac and Edit Mac on both platforms: the full Remote Login (SSH) label is visible, values stay aligned, and empty fields use 5900/22. Check large text and a narrow iPhone.
- On iOS, choose every Open on Tap mode. The native menu marks the current mode; the selected value and menu indicator share a baseline and stay trailing-aligned.
- In Sync & Security, expand What Syncs and Manage Sync. Read the credentials information sheet; passwords/private keys are explicitly excluded from app sync.
- Open Delete Mac Data from iCloud. Cancel the review, then cancel the final confirmation. Neither cancellation changes sync or removes data. Perform confirmed deletion only with synthetic test data after disabling sync on other test devices; verify local Macs/logins are kept and delayed propagation is reported without claiming a global wipe.
- Verify Require Unlock describes the available Face ID/Touch ID/passcode method on iOS. Check actual device unlock after backgrounding. Mac keeps its existing screen-sleep/session-lock behavior.
- In every session mode, use Customize from the floating menu to reach the preview editor. iOS Trackpad & Keyboard remains available; Mac has Desktop/Terminal.
- In Pro, benefits are informational, purchase/trial terms are beside their actions, and Free Version is a short list. Check portrait, landscape and large text; purchase/restore controls remain reachable.
- Test StoreKit product loading, trial start, purchase, restore, cancellation, offline errors and pending approval. Progress names the current operation in a stable area; system cancellation is quiet and pending approval doesn't block the app. Use StoreKit fixtures for local tests, then the signed TestFlight build for physical acceptance.

## Controls editor follow-up

- On iOS, check the quick-action preview and session menu in portrait, landscape and large text. Two wider columns become one column at accessibility sizes. The editing preview contains only editable actions and grows to fit them.
- Open Add Action, add a standard, shortcut or saved text, and verify the sheet closes to the selected inspector. Already-visible standards are absent. Cancel the controls editor to discard all changes.
- Add a shortcut in each mode. Its initial name follows the key combination until manually renamed; existing custom names remain unchanged. Ctrl, Option, Shift and Cmd stay on one line with full VoiceOver labels. Terminal excludes Cmd.
- Use Insert Symbol in a shortcut name, including an emoji name. Check insertion at the caret and replacement of selected text, then save and reopen.
- Check Saved Text empty, single-line, multiline and over the 256-character limit. The field grows until it scrolls, stays readable with the keyboard open, and preserves spaces and trailing newlines. Cancel does not persist the draft.
- On iOS, check Touch & Haptics: Show Touch Indicators and Haptic Feedback apply to all Mac connections on that iPhone or iPad. Mac only shows relevant desktop/terminal settings.


### iOS local backup and restore

- Create a backup with iCloud Sync off, save it in Files, and restore it on another signed iPhone or iPad. Compare Mac order, connection settings, keyboard rows, saved actions, positions and recovered alternatives. Restored Macs must request sign-in and trust confirmation.
- Cancel both system file pickers and the restore preview; saved data must stay unchanged. Reject invalid, oversized and newer-format files before any imported data is saved.
- Restore with iCloud Sync on, then confirm that this device stays off and the existing cloud copy is kept. Re-enable only deliberately; verify normal causal reconciliation on two signed devices.
- Use Restore Previous Data, including after an app restart. Check portrait, landscape and large text, with all confirmation and recovery actions reachable.
