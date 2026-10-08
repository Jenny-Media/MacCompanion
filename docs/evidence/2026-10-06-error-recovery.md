# Native error and recovery implementation

Date: 2026-10-06. The user approved the interactive recovery mockups and the
six-step implementation/internal TestFlight plan in the design audit.

## Implemented

- Shared typed recovery notices and native cards distinguish failures, progress,
  cancellation, pending purchases and uncertain outcomes. Actions have accessible
  targets, Light/Dark appearance, Dynamic Type and expandable bounded local details.
- Terminal preserves native DNS/TCP categories and uses typed SSH failures. A key
  rejection explains that the public key may need adding; it does not claim that
  the host lacks it. Server identity checks still precede authentication.
- **Terminal Access** in each Mac's settings includes account, key selection,
  **Set Up Key on This Mac**, and free **Manual Key Setup**. Terminal login exposes
  setup beside the selected key and on a confirmed rejection. Automatic setup
  still requires Pro/trial; importing or selecting a key is distinct from setup.
- Setup tracks not-sent, sent, acknowledged and verified phases. A cancelled or
  timed-out command may already have installed the public key. **Test Key Login**
  uses fresh key-only authentication, without sending another installation command
  or requesting password authentication. Failed verification preserves the prior
  saved key association and password. Private keys stay on the iPhone.
- Desktop failures use the shared presentation. After a rendered frame, the last
  frame remains visibly inactive with Reconnect/Edit Login. A compatible display
  layout permits viewport restoration. Input and remote commands are never replayed.
  Saved-login failure before connection stops the spinner and exposes editable fields.
- Unreadable saved Macs/keys/controls/iCloud history show protected unavailable
  states with real retry reads. They do not pretend the data is an empty library
  or overwrite it. Save errors retain editor drafts. Controls offer standard
  controls when the stored customization cannot be read.
- Key import/export, cloud removal, StoreKit recovery, app lock and field validation
  now use contextual guidance. Picker/authentication/purchase cancellation is neutral;
  uncertain purchases offer Restore/history instead of claiming a charge outcome.

The direct-client specification and the single indexed fixture corpus document
classification, setup certainty and pure verification. No wire authentication,
host-trust policy, entitlement, legacy grants or Mac-helper requirement was added.
No raw vendor output, passwords, private keys, input or screen content was added to
diagnostic telemetry. Screenshots use synthetic data and remain outside Git.

## Verification

- Stable Xcode 27.0 (27A266a), `bash scripts/validate.sh`: exit 0. The log is
  `/private/tmp/maccompanion-recovery-validation.log`.
- Native Simulator suite: **93 tests, zero failures**, including typed fixture
  classifications, data-preserving retry, saved-login recovery and real local SSH
  tests for trust ordering, cancellation uncertainty and key-only verification.
  Result: `/private/tmp/maccompanion-recovery-simulator-20261006/QA/Results.xcresult`.
  A previous timed-out runner overlapped the first result bundle. It was allowed
  to finish, the mixed artifacts were retained separately, and one clean rerun
  passed all 93 tests. `xcresulttool` confirms Passed, zero failures or skips.
- Twenty synthetic Simulator screenshots cover Terminal rejection, Mac settings,
  setup, uncertain setup, trust, saved-data failure and native Desktop recovery.
  Light, Dark and large-text layouts were visually reviewed; long content scrolls.
- OpenSSH interoperable private export and public-key installation checks passed,
  including authorized_keys preservation, permissions, idempotency and link rejection.
- The normal device build passed and was archived as **1.0 (3)** with the existing
  app/widget identities, distribution certificate, profiles and Keychain groups.
  Strict signature and exact input-hash checks passed. The signed application
  binary SHA-256 is `9e3cc2190c068827a49a508b62c689f95f9c59d604761a5ecfbb4230c10a922c`.

## Internal delivery

The verified archive and reports are under
`/private/tmp/maccompanion-recovery-testflight-20261006/`.
Xcode TestFlight Internal Only upload completed at 01:44 local time and Organizer
marks build 3 Uploaded to Apple. An initial account check failed; the retry
succeeded with the same account. The existing non-blocking OpenSSL dSYM warning
remains; application and widget symbols are included. Apple processed build
`8545ea6f-e3e7-4223-becc-dbf130efb394`. The same standard-encryption and
outside-France testing answers were reviewed and saved. Focused What to Test
notes were saved. The existing **Internal Testing** group is assigned with its
one existing tester. The group's Builds page confirms **1.0 (3), Internal,
Testing**, expiring in 90 days. Physical TestFlight acceptance remains separate.
The development dependency graph remains `releaseAdmitted = false`;
this checkpoint is not a public App Store release.
