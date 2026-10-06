# Named SSH keys, remote setup, Terminal keyboard and Lifetime Pro

## Implemented scope

- Independent named Ed25519 key UUIDs, create/import/rename/delete, public export
  and authenticated passphrase-encrypted OpenSSH private export.
- Neutral shared/separate-key behavior with explicit per-Mac/account selections.
  Durable idempotent migration retains unreadable/failed legacy records. Removing
  a Mac clears its association without deleting shared key material.
- Install Key on This Mac lives in the individual Mac settings. Standard SSH
  host trust precedes bootstrap password/key authentication. Only a public key is
  appended, preserving existing entries/options. A fresh key-only connection to
  the same verified endpoint must succeed before changing the saved selection.
  Failure/cancel/timeout preserves preferred login and saved bootstrap password.
- Permanent software-keyboard number row, one-shot Ctrl/Alt with explicit hold
  locking, Shift, navigation/function keys, common shortcuts and local copy/paste.
  Pro adds a custom row and protected local snippets.
- Permanent free tier: one Mac/key, unlimited session duration, Desktop/input/basic
  Terminal, standard keyboard, key import/export, connection/display settings,
  security and accessibility. Existing excess records remain editable/exportable;
  users can choose the active free Mac/key. No record deletion or active-session
  termination on entitlement changes.
- Verified StoreKit non-consumable Lifetime Pro with purchase, restore, current
  entitlements and refund updates. Multiple Macs/keys, automatic setup and custom
  keyboard/actions/snippets are Pro features. No subscription/account/backend.

## Source and protocol admission

The normative direct-client profile and indexed fixture were updated before
implementation. The fixture manifest is still the only fixture index. Standard
OpenSSH export uses bcrypt 32 and AES-256-CTR; import caps bcrypt at 128 rounds,
salt at 64 bytes, and checks all padding bytes including full-block padding.
Encrypted export exposed an existing Citadel mismatch (`rounds < 32`) and a
last-padding-byte omission; both are corrected and the vendored patch/source
lock hashes updated. Exec stderr now has the same response bound as stdout.

Xcode 27's SwiftTerm plugin requested the host generator under `Products/Debug`
while building its executable under an iOS products directory. The development
builder compiles the original clean, exact-pinned generator for macOS at the
requested path. It does not modify SwiftTerm or replace generated source.

## Verification

- Stable Xcode 27.0; Simulator iOS 27.0 in an isolated QA device/access group.
- 82 hosted native tests pass, zero failures (the opt-in screenshot test is skipped in the general suite):
  `/private/tmp/maccompanion-pro-simulator-20261005/QA/Results.xcresult`.
- Tests cover shared keys with different usernames, rename/selection stability,
  Mac removal, deletion, legacy migration/idempotency, corrupt-data preservation,
  device-only Keychain, encrypted export round trip, wrong passphrase, complete
  padding block and rejection of corruption in the final padding byte.
- Real loopback SSH tests verify host trust before credentials, ordered PTY input
  and resize, password/key login, changed-host rejection, setup bootstrap followed
  by a fresh key login, and preservation of preferred selection/password when
  verification fails. Synthetic server only; no user account/authorized_keys used.
- Local StoreKit tests exercise actual product lookup, purchase verification,
  restored/reloaded entitlement and refund update, plus indexed negative admission
  cases. A stale Apple Account prompt from the initial incorrect scheme was
  cancelled before the final run; foreground-dependent checks then all passed.
- Independent host OpenSSH accepts the fresh synthetic encrypted export and
  derives its expected public key. The actual generated setup command was
  redirected into a dedicated temporary fixture directory and checked for
  preservation, duplicates (including restrictive options), private permissions,
  symlink and hardlink rejection, and cleanup. Synthetic files were removed.
- The reviewed normal iPhone application builds successfully with source/dependency
  hash evidence under `/private/tmp/maccompanion-iphone-reviewed-device-20261005/build-report.json`.
  No Experiments target is linked into that app; the QA project is separate.
- Required `bash scripts/validate.sh` passes with stable Xcode and
  `MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1` (exit 0), including indexed fixtures,
  repository material, dependency admission, full package tests and platform
  compile checks. Final log:
  `/private/tmp/maccompanion-iphone-reviewed-install-validation-final-20261005.log`.
- The normal Simulator and iPhone builds are refreshed for the reviewed sources.
  The development-signed iPhone app and widget pass exact entitlement and deep
  signature checks, preserving the existing app identifier and Keychain identity.
  CoreDevice installation and launch succeed on the user's iPhone 18 Pro Max,
  database sequence 8364. Source hashes still match after delivery. Signed report:
  `/private/tmp/maccompanion-iphone-reviewed-signed-20261005/report.json`.

## Remaining external acceptance

The local `.storekit` file and its 19.99 test price are synthetic, not an activated
App Store product or an approved price. Real App Store Connect creation/price,
store review and protected release identity/signing gates remain separate.
Physical acceptance of key setup/export and terminal keyboard interactions remains
pending. The development update is installed and launched; no commit, push or public
release is performed here.
The client continues to require no Mac Companion macOS app/helper.

## Independent code and Simulator screenshot review

Three subagents independently reviewed SSH/storage/security code, UI/entitlement/
keyboard code, and Simulator screenshots. Confirmed findings were repaired:

- Clearing a selected key now changes the Terminal login back to Password.
- Shift maps the accessory number/punctuation symbols correctly. Backspace
  consumes one-shot modifiers while preserving native IME/text-input bookkeeping.
  Grouped native deletion emits one Ctrl/Alt deletion per logical call. Real SSH
  regression checks verify bytes, subsequent ordinary input, and the grouped case.
- SSH setup parses actual key fields before comments, including quoted options;
  key-like text in a comment cannot suppress installation. Host OpenSSH fixture
  checks cover both comments and quoted options.
- Initial Pro entitlement resolution precedes a denied paid action.
- A connected SSH socket previously enabled reads before its parser was attached.
  An early server banner could be discarded, causing an intermittent pre-login
  timeout. Reads now remain paused until all SSH handlers exist, then resume before
  authentication. A deterministic test observes the old discarded-banner path,
  delays attachment by 100 ms on the corrected path, and verifies successful
  authentication with a strictly matched host key. All six SSH integration tests
  pass. The security reviewer independently cleared this ordering repair.
- The account username keeps a persistent label, selected keys have explicit
  status separate from details, and installation uses a fingerprint disclosure
  and vertical authentication choices at accessibility text sizes.

The screenshot harness in `Experiments/NormalVNCViewportQA` is opt-in and not
linked into the normal app. Eleven production-view captures cover key library,
per-Mac selection, installation, key details/export, create/import, keyboard
settings, software keyboard rows, dark appearance, large text and Pro. They use
synthetic data and the local StoreKit test configuration. Capture test passed;
reviewers found no further concrete issue after repairs and re-review. The bare
terminal-controller capture and root key-detail capture omit the normal navigation
shell. Screenshots remain outside Git in the task's visualization directory.

A pre-existing native menu test assumed a fixed UIKit presentation duration.
It now waits for the presentation transition before invoking a submenu selection;
this changes test synchronization, not product behavior.

The installation-time full gate exposed another pre-existing readiness assertion in
the legacy client router test. Publishing bridge channels precedes the asynchronous
ready callback, so waiting for channel presence could assert too early. The test now
waits for the existing ready signal with the same bounded deadline. The direct client
does not instantiate that legacy router. Full stable-Xcode validation passes after
this test-only correction; no installed application source changed.
