# Keyboard layout sync in iOS 1.1

The existing iCloud Sync switch also controls the Terminal and shared Screen
Sharing / Trackpad & Keyboard row layouts on iPhone and iPad. Sync reads on
enable, foreground, unlock, explicit Refresh iCloud, and local layout saves.
It uses synchronizable Keychain, like the saved Mac metadata; delivery depends
on the signed-in account's iCloud Keychain availability and propagation.

Row order, row names, visibility, alignment, initial scroll edge, and built-in
keys / controls and row restore presets sync. Saved shortcut definitions, saved text and their button
placements remain on each device unless the separate saved-controls option below is enabled. Incoming rows retain local saved buttons at
the end of their matching row. If that row was removed remotely, those buttons
move to the main row rather than disappearing. Saved menu definitions and positions follow that separate option; credentials
and trust records remain local.

The isolated `media.jenny.maccompanion.cloud-keyboard-layouts.v1` service does
not change the 1.0 saved-Mac schema. Older clients ignore this service. Each
writer retains one bounded version per controls family; revision and writer UUID
resolve concurrent edits deterministically. A new device reads cloud versions
before publishing defaults. Turning sync off preserves cloud records and tracks
later local edits without cloud access. Remove iCloud Data removes the metadata, layout and optional saved-content services.

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
preparation triggers a refresh. Saved text and shortcuts remain local unless
their separate sync option is enabled.
Native regressions cover startup with only per-Mac legacy content, plus edits
after an import-journal failure with the remote revision retained across Retry
and restart.


## Optional shortcuts and saved text

The iPhone/iPad consent footer says “Encrypted iCloud sync.” What Syncs and
Credentials & iCloud explain that iCloud Keychain must be enabled on each device.
The separate “Sync shortcuts & saved text” option starts off and requires its own
confirmation. It includes shortcut sequences, saved text and their keyboard and
floating-menu positions; it never includes credentials, trust, unsaved composer
drafts, clipboard or session history. Imported controls never execute themselves.
The flag is local to each installation, and the main iCloud switch must also be on.

The independent saved-controls service merges definitions individually, retaining
concurrent additions and using revision/writer order for conflicts and deletion
tombstones. Pending offline edits and fetched clocks are kept in a local Keychain
journal before imports. Layout and content imports are marked so neither becomes
a new local edit. Missing rows temporarily place their saved buttons on Main Row.

A 4096-byte saved text remains supported. Larger encoded definitions/placements
are split into bounded pieces, committed by a generation/length/digest head. Each
logical version is capped at 32768 bytes and the service at 512 wire records.
Incomplete delivery, malformed data, capacity or journal failure preserves local
content and shows a retry notice. No content is truncated to fit.

Turning either switch off retains existing local/cloud data. Delete Mac Data from
iCloud also removes saved-content records after admitted writes drain, preserves
local controls and clears this additional opt-in. Signed two-device propagation
still needs physical acceptance; synthetic transport tests establish merge and
failure behavior, not delivery through a real Apple Account.

The additional consent is bound to this device's non-migrating Keychain writer,
so restoring app preferences to another device cannot enable private-content
sync. Saved-content observers use committed profile identities and wait for
legacy collision migration to persist before projecting it. Import retry also
recognizes normalized fallback placements instead of publishing them as edits.
Cloud removal reaches the independent content service even if the Mac journal
cannot be read. A remembered content choice can be switched off while main sync
is off, before any future metadata-only re-enable.
