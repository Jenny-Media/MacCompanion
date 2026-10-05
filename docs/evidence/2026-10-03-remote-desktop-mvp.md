# Remote-desktop MVP and pairing access

Date: 2026-10-03. Local development updates; no public release.

## Product change

The product owner explicitly chose a remote-desktop-only MVP with one pairing
for remote access. The phone workspace exposes connection/recovery and Remote
Control. Observe and Approved Actions are deferred, and the local website now
explains displays/windows, keyboard/shortcuts, and trusted devices. The Mac
pairing sheet discloses screen, pointer, keyboard and eligible text access.

New normal-app pairings atomically store the device, local name, consumed
pairing ID, fixed `maccompanion.interactive.control` grant, initial epoch/revision
1, and minimal security event. A failed transaction leaves no partial device or
consumption. The wire completion reports the actual initial authorization.
Exact-key recovery supports both legacy and remote-desktop initial records;
changed or revoked authority cannot be recovered. Existing paired devices are
not silently expanded. Already Control-enabled devices need no re-pairing.

Session confirmation remains unchanged pending the product owner's choice.
Pairing transcript/signature encodings, host pinning, OS permissions, visible
Stop, device removal/revocation, and session/input fences remain authoritative.

## Verification

- `bash scripts/validate.sh` passes on stable Xcode 27.0 with 122 indexed fixtures.
  Private log: `/private/tmp/maccompanion-mvp-stable-validation-presentation-20261003.log`.
- Matching golden pairing vectors pass with the remote-desktop profile. SQLite
  failures at all three transaction fault points roll back. Both initial profiles
  pass lost-completion recovery, durable client publication and authentication.
- Normal Mac, Simulator and iPhone builds pass. Both native SDK provenance
  records bind source input SHA-256
  `95ab93fd30b0f4c9886bb48592e7bf5bfe58415588fc5300f024b5d6657c9494`.
- Local website checked at 1280px desktop and 430px phone widths: no horizontal
  overflow, no Observe/Act tabs, three remote-desktop feature cards. Preview:
  `http://127.0.0.1:4173/`. Captures remain private and are not committed.
- The live normal Simulator caught a missed client presentation guard which
  still accepted only monitor-only completion. The guard was fixed and its exact
  durable-completion regression now exercises both initial states.
- The extended final-source Simulator journey completes fresh pairing, reaches
  the single Control workspace and opens native video without a second grant.
  It stops at an undelivered Shared Display menu tap, before switching. That
  extended journey is not passed. Current-run keys, host and app state cleanup
  pass. Private report:
  `/private/tmp/maccompanion-mvp-pairing-final-qa-20261003/report.json`.
- The focused normal Simulator journey passes fresh TLS/SAS pairing without
  separate Control expansion, durable app restart, two native video sessions,
  compact keyboard, modifier/software-keyboard chords, shortcuts, pointer input,
  Stop/restart and exact current-run key/host/app-state cleanup. The signed
  isolated Mac consent is substituted; client user presence is not substituted.
  Final Mac input is synthetic, so this is not physical Mac-input acceptance.
  Private report:
  `/private/tmp/maccompanion-mvp-pairing-acceptance-qa-20261003/report.json`.
  Earlier pre-test attempts lacked the correct test checkout or selected an
  ambiguous signing certificate. The intermediate completion-failure run's key
  cleanup was unconfirmed; all diagnostics remain private.

## Installed updates

The signed Mac app and Agent are installed at
`/Users/yihong/Applications/Mac Companion.app`, with the existing service,
Keychain entitlements and all 119 verified Sunshine package files preserved.
Private receipt: `/private/tmp/maccompanion-mvp-final-mac-installed-20261003.json`.
Rollback: `/private/tmp/maccompanion-mac-pre-mvp-final-20261003.app`.

The signed normal update is installed and launched on iPhone 18 Pro Max with
existing pairing, app data, application identity, Keychain groups and provisioning
profile retained. Receipts: `/private/tmp/maccompanion-mvp-final-iphone18-install-20261003.json`
and `/private/tmp/maccompanion-mvp-final-iphone18-launch-20261003.json`.
Physical acceptance of the new pairing flow remains pending; launch is not
acceptance. Existing keyboard and branding work remains in this checkout.

View switching performance, connection reuse, background reliability, All
Displays, corresponding-source release closure and public distribution remain
separate pending work. No production-ready claim is made.

## Trusted-device session confirmation follow-up

The product owner explicitly selected “Pair once; no session confirmation.”
Both normal app compositions now select `trustedDevice`. Interactive session
starts sign the existing complete one-use challenge with the paired protected
session key. The host accepts only that paired key under this profile. The
legacy profile retains its presence-bound approval key; there is no cross-key
fallback or wire-controlled policy selection. Key protection, pairing keys,
grants, host pins, monotonic expiry, epochs/revisions, visible admission,
Stop and revocation remain enforced. Existing Control-enabled pairings require
no migration or re-pairing. Monitor-only records still need a one-time local
Control upgrade. The Mac pairing disclosure now explains prompt-free reconnect.

Specification and indexed fixtures were updated first. The existing authoritative
interactive cryptographic fixture now includes a conformance-only session-key
signature over the identical challenge input and cross-key rejection checks.
Regression coverage includes exact custody role, configured reconnect policy
retention, correct/wrong/replaced session keys, missing session key and missing
fixed Control grant. The normal UI removes misleading per-session Face ID copy.

The final-source normal native Simulator journey passes fresh pairing, durable
app restart, two video/input sessions, keyboard/modifier/shortcut and pointer
input, Stop/restart and cleanup. Its private report is
`/private/tmp/maccompanion-mvp-trusted-pairing-qa-20261003/report.json`.
Both SDK provenance records and all normal builds bind source input
`621cf66fdef567acdfa746c853ef828dfab86020a61193e6cc14d10b25802565`.
The test host substitutes disclosed Mac consent and synthetic final input; it
does not substitute client signing/presence or represent physical acceptance.

The first full run passes the new golden/signing/grant checks but exposes two
existing test-harness scheduling assumptions: a fake reply was delivered after
proof-send publication but before receive registration, and a listener test
bounded readiness by 1,000 scheduler yields. The tests now require an actual
pending receiver before delivering a fake frame, and listener readiness uses a
bounded monotonic time deadline. Product networking code is unchanged by those
test fixes. The corrected client network target passes all 55 tests and the exact listener
checks pass. Private log:
`/private/tmp/maccompanion-mvp-trusted-network-synchronized-20261003.log`.

Signed updates are installed on both apps. The Mac menu and Agent launch, all
119 native host package files remain verified, and existing service identities,
Keychain groups and the native package catalog are retained. The iPhone 18 Pro
Max update installs and launches with the same bundle ID, signing entitlements,
provisioning profile and app data; no uninstall or pairing reset occurs.
Receipts:
- `/private/tmp/maccompanion-mvp-trusted-mac-installed-20261003.json`
- `/private/tmp/maccompanion-mvp-trusted-iphone18-install-20261003.json`
- `/private/tmp/maccompanion-mvp-trusted-iphone18-launch-20261003.json`

Rollback Mac app:
`/private/tmp/maccompanion-mac-pre-mvp-trusted-20261003.app`.
Physical remote-control acceptance remains pending. View-picker switching,
background/recovery reliability and release gates retain their outstanding status.
Final required stable Xcode 27.0 validation passes with 123 indexed fixtures,
exit 0 and no failed-test/footer signals. The full rerun passes the corrected
client network target (55 tests), Agent target (275 tests), all remaining unit
and lab targets, platform builds and final native selected-context checks.
Log: `/private/tmp/maccompanion-mvp-trusted-stable-validation-clean-20261003.log`.
The website is updated and visually verified at `http://127.0.0.1:4173/`.
The screenshot remains private:
`/private/tmp/maccompanion-mvp-trusted-website-20261003.jpg`.
Changes remain local and uncommitted; no public release occurs.
