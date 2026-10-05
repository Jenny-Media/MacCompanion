# Saved login retention and shared endpoints

## Diagnosis and corrected behavior

The user correctly observed both previous behaviors. `DirectMacLibraryV1.save`
called the per-Mac credential deletion hook before writing address/port edits.
It also rejected an endpoint found in another saved Mac. The load path enforced
the same cross-record uniqueness. These were explicit policies, not mistyped
login information or a Passwords/1Password collision. Deleting before a failed
library write could also lose a login even though the edited record was not saved.

The direct Screen Sharing profile and its existing indexed fixture now specify:

- Editing addresses, port or name preserves the login for the same Mac UUID.
  Adding/removing local or Tailscale routes does not delete the saved credential.
- Different records may share an address/port and keep independent logins and
  preferences. The editor shows which entries also use that endpoint, with an
  informational note that does not disable Save or require confirmation.
- UUID uniqueness, valid route/port bounds, and duplicate-address rejection within
  one record remain. A duplicate address inside one record has no fallback benefit.
- Forget Saved Login, opting out of retention, and removing a Mac still delete
  that UUID's credential. Editing an address does not verify host identity; the
  editor explains using Forget Saved Login when repurposing an entry.

The implementation removes both cross-record endpoint rejection paths and removes
credential deletion from `save`. Existing schema-1/schema-2 records remain readable.
The warning resolves normalized addresses and the configured port, excludes the
currently edited record, and caps displayed names. No protocol, authentication,
cryptographic vectors, Keychain groups or legacy grants change.

Logins already deleted by the previous update cannot be restored by this code.
The user must enter those once again; subsequent route edits preserve them.

## Verification

Toolchain: `/Applications/Xcode.app`, Xcode 27.0.

- **36 hosted tests passed, 0 failed, 0 skipped**:
  `/private/tmp/maccompanion-library-policy-tests-20261004.xcresult`.
- Five edit cases from the sole indexed direct-client fixture use actual synthetic
  Keychain credentials: alternate-address addition/removal, replacement, reorder
  and port change. All retain the original UUID's login.
- A shared-endpoint test persists/reloads both accounts, verifies separate actual
  synthetic Keychain entries, checks the informational lookup, and verifies that
  Forget/Remove affect only the selected account.
- A forced failed library write preserves both the original in-memory record and
  its saved credential. Existing migration, unreadable storage, session controls,
  native lifecycle, ActivityKit, display and input tests also pass.
- Actual Simulator editor accepts a second synthetic record at `127.0.0.1`, shows
  “Also used by My Mac. Each saved Mac keeps its own login,” enables Save, then
  returns to a list containing both entries with the same endpoint. No real
  credential, endpoint or typed content was read.
- Required `bash scripts/validate.sh` exits 0:
  `/private/tmp/maccompanion-library-policy-validation-20261004.log`.
- Normal iPhone build passes; 480 source input hashes match the signed app.
  Existing device profile, app Keychain group and deep signatures verify.
  Signed binary SHA256:
  `725fe7bb995acf737f54e3d53713bed69cd26996388ac1361590d7e1450d1634`.

## Installation boundary

Signed update:
`/private/tmp/maccompanion-library-policy-signed-ios-20261004/Mac Companion.app`.
The initial install attempt fails with CoreDevice error 4016 because the device
has no assertable trusted connectivity/services/power state. The subsequent
device listing confirms the previously paired iPhone 18 Pro Max tunnel is
unavailable. After the user unlocks the phone, the retry installs successfully,
database sequence 8188, preserving app data. The correction's credential/address
behavior still needs physical acceptance. `devicectl` launch also succeeds.
There was no uninstall, credential
extraction, commit or publication.
