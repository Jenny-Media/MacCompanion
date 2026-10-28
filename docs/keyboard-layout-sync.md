# Keyboard layout sync in iOS 1.1

The existing iCloud Sync switch also controls the Terminal and shared Screen
Sharing / Trackpad & Keyboard row layouts on iPhone and iPad. Sync reads on
enable, foreground, unlock, explicit Refresh iCloud, and local layout saves.
It uses synchronizable Keychain, like the saved Mac metadata; delivery depends
on the signed-in account's iCloud Keychain availability and propagation.

Row order, row names, visibility, alignment, initial scroll edge, and built-in
keys / controls and row restore presets sync. Saved shortcut definitions, saved text and their button
placements sync under the same main setting on iOS 1.1. Incoming rows retain local saved buttons at
the end of their matching row. If that row was removed remotely, those buttons
move to the main row rather than disappearing. Saved menu definitions and positions use the same setting; credentials
and trust records remain local.

The isolated `media.jenny.maccompanion.cloud-keyboard-layouts.v1` service does
not change the 1.0 saved-Mac schema. Older clients ignore this service. Each
writer retains one bounded version per controls family; revision and writer UUID
resolve causally concurrent edits deterministically, retaining other versions in local recovery. A new device reads cloud versions
before publishing defaults. Turning sync off preserves cloud records and tracks
later local edits without cloud access. Remove iCloud Data removes the metadata, layout and saved-content services.

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

Sync is automatic after enabling the main switch. Each service initializes its
Terminal and shared remote-Mac profiles through the existing controls store before
capturing baselines or reading cloud data. No Mac selection, connection, controls
editor visit or additional setup action is required. Current saved controls are
retained. Per-Mac compatibility setup from unpublished builds is not supported.
The controls store persists a current-format header even when the existing rows
and saved content need no other changes, so sync can read the initialized profile.
Off-state baseline reads remain read-only. Storage or capacity failures preserve
local controls and expose retry information in Manage Sync.
Native regressions cover automatic fresh-profile initialization and import without
opening controls, retention of current shared controls, plus edits
after an import-journal failure with the remote revision retained across Retry
and restart.


## Shortcuts and saved text

Accessory keys pinned from Keypad use the same definition service, including
their keyboard and floating-menu positions. Only the key, title, identity and
placements sync; inactive shortcut/text payloads stay local. Existing local key
updates retain that inactive local data. Key imports never press a key.

Normalized legacy Return/Interrupt definitions retain their `builtIn` origin.
Only unchanged definitions with that provenance are excluded as local defaults.
An explicit palette selection clears the marker, including when it reuses an
existing definition. Older unmarked definitions are kept eligible rather than
guessing their origin from their name or key values; this can include an old
default whose provenance had already been discarded. Import execution still
depends on the action's category, never its migration marker.

The iPhone/iPad consent footer says “Encrypted iCloud sync.” What Syncs and
Credentials & iCloud explain that iCloud Keychain must be enabled on each device.
The main iCloud Sync switch includes shortcut sequences, saved text and their
keyboard/menu positions by default on iOS 1.1, including when that main switch
was already enabled. There is no separate content option. The main switch still
starts off on a new installation; its confirmation names all synced categories.
Credentials, trust, unsaved composer drafts, clipboard and session history stay
local. Imported controls never execute themselves. Obsolete content-consent
preferences do not enable, disable or gate the main setting.

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

Turning the main switch off retains existing local/cloud data. Delete Synced Data from
iCloud also removes saved-content records after admitted writes drain, preserves
local controls and turns main sync off here. Signed two-device propagation
still needs physical acceptance; synthetic transport tests establish merge and
failure behavior, not delivery through a real Apple Account.

Saved-content observers use committed profile identities after owner
initialization. Import retry recognizes
normalized fallback placements instead of publishing them as edits. Cloud removal
reaches every independent service even if the Mac journal cannot be read.
Removal attempts each service before reporting any transport or local-journal
failure; unreadable local history and local controls are preserved.

Saved-button imports reserve saved placement identities before composing them
with built-in keys. Editor replacements can retain an imported key's identity;
colliding built-in identities are remapped, and independently merged saved
buttons and floating-menu favorites receive stable aliases when necessary. Repeated imports remain valid
without changing saved content or publishing normalization as a local edit.

The iOS copy audit uses concise native icon rows for gestures, server identity,
manual key setup and settings details. Security commands, matching-key-type
checks, file permissions, deletion consequences and local-data retention remain
explicit. These presentation changes do not alter input or SSH authentication.

Sync & Security keeps a concise status and navigation to What Syncs and Manage
Sync. Per-service notices and retry controls stay in Manage Sync. The enable
sheet keeps both actions visible and starts taller at ordinary text sizes, with
a large scrolling presentation for accessibility. Cloud exclusion uses the
crossed-out cloud; deletion uses a destructive trash action. Local-login details
are available from What Syncs rather than repeated as a prominent warning.


## Conflict recovery

Routine sync stays automatic. Each edit records the per-writer revisions known
from its last applied profile, including earlier edits on the same device. Fetching
new data before uploading an offline edit does not make that edit a successor.
Sequential edits produce no recovery copies. Independent saved definitions merge;
concurrent edits to the same definition keep the non-selected version in Recovered
Changes. A concurrent deletion keeps the item out of the active library and keeps
the edited version recoverable. Layouts select one complete arrangement and retain
the alternative instead of blending row positions.

Sync & Security shows a nonblocking recovery notice when copies are available.
A single layout opens directly with Review Layout; multiple copies open Recovered
Changes. Manage Sync retains the same recovery entry. Inspect a version, Restore
as Copy for saved content, or Use This Layout.
Restoring saved content creates a new identity and restores its button positions;
it never runs input. Switching layouts retains the previous layout in recovery.
Discard actions affect recovery copies only and retain dismissal high-water marks
so repeated refreshes do not recreate them. Discard All has an explicit confirmation.
Start over with iCloud uses the existing scoped deletion review; current local
data and recovery remain. Turning sync back on seeds from current local data.

Recovery payloads, causal baselines and import receipts stay in the device-only
controls profile. A saved-content import and its baseline are one Keychain write.
If the following journal write fails, retry/restart compares later local changes
against that applied receipt; a deleted import cannot return. Keyboard history
now uses device-only Keychain storage keyed by the local writer, matching controls
and writer identity. Synthetic file-backed history is also writer-bound, so a
restored file cannot publish a new device's defaults over cloud customizations.
Existing unpublished file journals are not migrated or deleted.


The first local keyboard customization also saves its pre-edit baseline atomically
with the profile. A failed first journal write followed by restart cannot turn that
edit into an untouched baseline. Import receipts keep their existing role. Retry can
distinguish an unedited import followed by another remote edit from a genuine
local change back to the pre-import layout. Reset retains causal clocks and
marks current layouts and known saved-definition deletions for reseeding, so
delayed old cloud records cannot replace current data when sync is re-enabled.

Reset reseeding remains explicit until new local versions are durably prepared.
A matching first stale layout cannot consume it. Non-editing notifications such
as recovery discard cannot consume saved-content reseeding or known deletions.
Recovery confirmations use alerts with an explicit Cancel on phone and tablet.

Both controls services durably record reset/reseeding intent before removing cloud
copies. If that local write fails, the affected cloud service is left intact and
removal reports failure. A restart after successful deletion retains the intent to
upload unchanged local controls when sync is enabled again. The parent uses the
same write-ahead reset when its Mac journal prevented creating a controls engine;
an unavailable writer identity cannot authorize deletion without that bookkeeping.
