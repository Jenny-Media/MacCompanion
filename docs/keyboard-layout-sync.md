# Keyboard layout sync in iOS 1.1

The existing iCloud Sync switch also controls the Terminal and shared Screen
Sharing / Trackpad & Keyboard row layouts on iPhone and iPad. Sync reads on
enable, foreground, unlock, explicit Refresh iCloud, and local layout saves.
It uses synchronizable Keychain, like the saved Mac metadata; delivery depends
on the signed-in account's iCloud Keychain availability and propagation.

Row order, row names, visibility, alignment, initial scroll edge, and built-in
keys / controls and row restore presets sync. Saved shortcut definitions, saved text and their button
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
remain usable locally and show a sync notice; no layout is truncated. A durable
local pending marker prevents refresh or restart from applying an older cloud
layout over an unpublishable edit. Projected-layout fingerprints distinguish real
layout edits from local-only menu, saved-definition or expansion saves. Before a
local save writes the profile, any missing baseline is captured from the still-stored
controls. This also covers initialization beneath the app-lock cover followed by
unlocking while sync is off, without contacting cloud. The first genuine layout
edit is still recorded. Journal
write failures pause import until the current local profile can be reconciled
against fetched revision history before another import. Fetched history is
journaled before profiles are applied, so an import cannot discard its observed
clock. Malformed
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

Sync baseline reads do not commit local profile migrations. Shared remote-Mac
rows wait until the existing Screen Sharing / Trackpad & Keyboard loader has
imported legacy per-Mac definitions and menus with its Mac context. That local
preparation triggers a refresh; saved text and shortcut content remain local.
Native regressions cover startup with only per-Mac legacy content, plus edits
after an import-journal failure with the remote revision retained across Retry
and restart.
