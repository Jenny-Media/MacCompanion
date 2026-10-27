# Keyboard layout sync in iOS 1.1

The existing iCloud Sync switch also controls the Terminal and shared Screen
Sharing / Trackpad & Keyboard row layouts on iPhone and iPad. Sync reads on
enable, foreground, unlock, explicit Refresh iCloud, and local layout saves.
It uses synchronizable Keychain, like the saved Mac metadata; delivery depends
on the signed-in account's iCloud Keychain availability and propagation.

Row order, row names, visibility, alignment, initial scroll edge, and built-in
keys / controls sync. Saved shortcut definitions, saved text and their button
placements remain on each device. Incoming rows retain local saved buttons at
the end of their matching row. If that row was removed remotely, those buttons
move to the main row rather than disappearing. Menus, credentials and trust
records remain local.

The isolated `media.jenny.maccompanion.cloud-keyboard-layouts.v1` service does
not change the 1.0 saved-Mac schema. Older clients ignore this service. Each
writer retains one bounded version per controls family; revision and writer UUID
resolve concurrent edits deterministically. A new device reads cloud versions
before publishing defaults. Turning sync off preserves cloud records and tracks
later local edits without cloud access. Remove iCloud Data removes both services.

The existing transport limit is 4 KiB per encoded version. Oversized layouts
remain usable locally and show a sync notice; no layout is truncated. Malformed
remote data or an unreadable local journal produces a notice and preserves local
controls. Refresh iCloud retries the journal read.

`KeyboardCloudSyncTests` covers projection privacy, local saved-button retention,
malformed and oversized records, concurrent writers, offline changes, restart,
new-device import, sync-off behavior and cloud removal. `KeyAndCloudTests` keeps
the existing Mac metadata / credential boundary covered. These synthetic
transport tests do not prove real-account cross-device propagation. Before a
1.1 release candidate, verify two signed physical iOS / iPadOS devices on the
same iCloud account, including sync off/on, foreground refresh, local saved text
retention and Remove iCloud Data.
