# iOS 1.1 candidate rehearsal

Target **1.1 (167)** from TestFlight. This is an execution checklist, not a
record of completed physical tests. Use disposable data on reviewer-controlled
devices and a test Mac. Do not change a personal Mac's Sharing, network or
security settings as part of materials preparation.

## Core connection rehearsal

- [ ] Record exact iPhone/iPad models, OS, installed version/build and test Mac.
- [ ] Follow [App Review notes](en-US/app-review-notes.txt) from a clean app state:
  built-in Remote Login and Screen Sharing, Quick Connect, Local Network access,
  independently matched SSH fingerprint, optional saved Mac login.
- [ ] Verify Desktop updates, pointer and trackpad delivery, harmless keyboard
  input, Compose Text, modifiers and Escape. Check key previews cancel on scroll
  and layout changes without sending an extra key.
- [ ] Verify Terminal and individual-file SFTP using the shared saved login;
  exercise a separately configured SSH key/password where applicable.
- [ ] Check portrait/landscape, resized iPad windows, larger text, app return and
  disconnect. Record physical Duo Book and both Tabletop directions separately
  using TestFlight; Simulator geometry is separate evidence.

## Backup and restore

- [ ] Add synthetic saved Macs and disposable keyboard layouts, shortcuts, menus
  and saved text. Create Backup with iCloud Sync off. Verify Files opens with an
  editable filename containing local date, time to the second and iPhone/iPad.
- [ ] Transfer the file to a second device and preview before restoring. Verify
  cancel and invalid-file selection preserve current data.
- [ ] Disconnect sessions, confirm restore and relaunch. Check saved Macs,
  connection settings, both keyboard layouts, shortcuts, menus, saved text,
  placements and recovered alternatives. Verify restored Macs require sign-in
  and fresh independent identity confirmation.
- [ ] Verify Restore Previous Data restores the prior local state after relaunch.
- [ ] Verify sync is off after restore and existing cloud data remains. Re-enable
  sync only deliberately, and do not delete cloud data during a restore test.
- [ ] Inspect a disposable backup for credential/trust exclusion. Keep even
  synthetic backup/input fixtures and screenshots outside application Git.

## Signed iCloud acceptance

- [ ] On two signed devices with the same Apple Account and iCloud Keychain,
  deliberately enable iCloud Sync and check Mac settings, both keyboard layouts,
  shortcuts, saved text, menus and placements after foreground/relaunch.
- [ ] Make independent and conflicting edits, then check automatic merge,
  Recovered Changes, Restore as Copy, Use This Layout, cancellation and undo.
- [ ] Confirm passwords, SSH private keys and trusted Mac identities stay local.
- [ ] Check sync-off local edits and later deliberate re-enable. Use disposable
  cloud data for any separately approved cloud-deletion rehearsal.

## Store handoff

- [ ] Read Apple's latest response to the existing VPN clarification. Resolve
  the initial-version workflow before changing the rejected 1.0 record.
- [ ] Check the local [copy](README.md), [screenshot handoff](screenshots.md),
  App Privacy, encryption/export answers, IAP items, contact and locales.
  Preserve France's existing exclusion, URLs and manual release.
- [ ] Recheck support/marketing pages for sync and backup accuracy; any website
  publication needs separate authorization.
- [ ] Keep the production submission held until the owner authorizes it.

For results, record date, operator, candidate, exact device, steps, outcome and
evidence path for every executed check. Existing 1.0 owner acceptance and 1.1
synthetic tests do not fill these boxes.
