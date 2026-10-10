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

## 11. Settings and error states

- [ ] Open Settings from the library and check the iCloud status. Labels match their destinations and current state.
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
