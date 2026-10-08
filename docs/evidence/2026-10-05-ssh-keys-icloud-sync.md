# SSH keys and optional iCloud library sync

## Scope and implementation

The existing Terminal was password-only. Added an explicit Password/SSH Key choice,
per-Mac key management from Terminal and Edit Mac, Ed25519 creation and OpenSSH
import (including AES-CTR/bcrypt encrypted keys), public-key copying and installation
instructions. Keys use cryptographic system randomness and standard SSH user-auth;
host fingerprint verification still runs before credentials. No password fallback
is used for key login. Private seeds remain in WhenUnlockedThisDeviceOnly Keychain;
passphrases are used once for bounded import on a detached task and never stored.
Only the public line can be exported. Removing a key is confirmed and does not
claim to revoke authorized_keys on the Mac. Imports are bounded to 32 KiB and
bcrypt rounds 1–128; unknown algorithms, malformed keys and public/private mismatch
are rejected. Ed25519 is supported; RSA/ECDSA/hardware keys are not yet supported.

Sync defaults off per installation and requires a privacy consent screen. The
selected scope is saved Macs and display/input settings only. Passwords, private
keys, accepted host keys, text/actions and app-unlock consent never enter sync
payloads. Unlike ordinary iCloud key-value storage, this uses synchronizable
generic-password items in the existing Keychain group; no new permanent Apple
capability or container is created. Privacy depends on Apple Account and iCloud
Keychain protection. Local version journals support offline edits, per-device
logical revisions, deterministic conflicts and tombstones. Device writer identity
is in device-only Keychain so restored backups do not clone a writer. Corrupt,
unsupported, oversized or duplicate data preserves local data. Disable retains
local Macs and cloud copies. Separate confirmed deletion warns to disable other
devices first. Foreground/manual refresh is gated by app unlock; session traffic
and Mac helper behavior are unchanged. Status never claims Apple has delivered a
local submission to another device.

Normative profile and indexed fixture were updated first. Ephemeral test keys are
generated with ssh-keygen under /private/tmp and are included only in the disposable
QA test bundle; no private key, credential or screenshot is committed.

Apple references:

- [Keychain synchronization attribute](https://developer.apple.com/documentation/security/ksecattrsynchronizable).
- [Secure Keychain syncing](https://support.apple.com/guide/security/secure-keychain-syncing-sec0a319b35f/web).
- [iCloud data security](https://support.apple.com/en-us/102651).
- [Key-value storage restriction for sensitive data](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).

## Verification

- 73 hosted Simulator tests pass, zero failed:
  `/private/tmp/maccompanion-key-cloud-final-tests-20261005.xcresult`.
- Added real local SSH-server key authentication before/after explicit host trust,
  rejection without password fallback, ssh-keygen encrypted import and wrong
  passphrase/unsupported-key rejection, device-only key retention across address
  changes, indexed cloud merge/deletion cases, two simulated devices, offline edits,
  corrupt cloud preservation, secret-exclusion checks and actual synchronizable
  Keychain read/update/delete in a synthetic isolated service.
- The first whole-suite key-auth check exceeded the five-second synthetic wait.
  A phase-labelled isolated rerun and two subsequent full suites passed without
  changing the SSH implementation. This is retained as provisional timing evidence,
  not evidence of a production reliability guarantee.
- Visual inspection verifies key setup, generated public-key instructions, iCloud
  default-off setting and explicit privacy alert. No user's cloud sync was enabled.
- Normal iPhone build and frozen-source/deep-signature checks pass, with unchanged
  Keychain group and existing device profile:
  `/private/tmp/maccompanion-key-cloud-signed-ios-20261005/report.json`.

- Required full stable-Xcode validation exits 0:
  `/private/tmp/maccompanion-key-cloud-validation-20261005.log`.
- Installed on iPhone 18 Pro Max after completion, preserving app data (sequence
  8332): `/private/tmp/maccompanion-key-cloud-install-20261005.json`.
  Sync remains default off. It was not enabled on the user's device.
- Automatic launch was denied because the iPhone is locked:
  `/private/tmp/maccompanion-key-cloud-launch-20261005.json`.
- Final material scan passes (1889 current files, 3489 historical blobs, 14 indexed
  material fixtures), and `git diff --check` passes. No commit or publication made.

Real iCloud delivery between Apple devices, physical key installation/login and
release acceptance remain separate from local API and simulated merge tests.
