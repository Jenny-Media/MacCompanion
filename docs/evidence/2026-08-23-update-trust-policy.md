# Direct-update trust policy checkpoint

Date: 2026-08-23

## Outcome

The first direct-distribution beta now has a closed, executable
[update trust profile](../../spec/update-policy/v0/profile.md) before an updater
dependency enters either permanent target. The profile admits only Sparkle
`2.9.6`, pinned to the complete upstream revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`.

That choice reflects current upstream security facts rather than the earlier
generic Sparkle 2 plan. Sparkle's latest 2.9.6 release adds installer archive
movement and package-validation hardening; 2.9.5 and 2.9.2 contain related
symlink and appcast-item fixes. The upstream documentation also states that
official builds should use HTTPS, Developer ID, EdDSA-signed archives, and
incrementing bundle versions. Signed feeds require pre-extraction archive
verification and are available in Sparkle 2.9.

Primary sources:

- [Sparkle 2.9.6 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6)
- [Sparkle security and reliability changes](https://sparkle-project.org/documentation/security-and-reliability/)
- [Sparkle setup and signed-feed guidance](https://sparkle-project.org/documentation/)
- [Sparkle publishing guidance](https://sparkle-project.org/documentation/publishing/)
- [Sparkle sandboxing and helper-signing guidance](https://sparkle-project.org/documentation/sandboxing/)

## Frozen boundary

The policy requires distinct protected beta and stable feed authorities,
signed feeds, verification before extraction, Ed25519 archive signatures,
Developer ID validation, notarized whole-bundle replacement, and no initial
delta or installer-package path. Automatic checks are permitted; automatic
downloads and installs are denied.

Installation requires a fresh five-minute local foreground confirmation,
cancel-on-foreground-loss, closed network admission, inactive and unambiguous
Control state, drained bounded work, a stopped Agent, and exact app/Agent
version compatibility. This avoids inventing an undocumented precise macOS
lock-state API: a locked Mac cannot issue or retain the required foreground
confirmation.

Developer ID and Ed25519 private authority remain external. One release may
rotate at most one of those trust anchors. Feed failure, signature failure, or
lost credentials never enables fallback, downgrade, or unsigned installation.

## Verification

`scripts/update_policy.py` enforces the closed canonical JSON shape, fixed
dependency revision, channel separation, trust requirements, runtime gates,
rotation rule, secret exclusion, bounded regular-file loading, and exclusive
mode-0600 writing. `scripts/validate_update_policy.py` passes 21 indexed cases,
including floating/old dependency, shared or embedded feed, automatic install,
unsigned feed, extract-before-verify, delta, active-Control, running-Agent,
long-confirmation, simultaneous-rotation, fallback, secret, duplicate-key,
noncanonical, symlink, hardlink, and oversize rejection. The suite is part of
`scripts/validate.sh`.

## Non-claims and next gate

No dependency was downloaded, no Package.swift or Xcode package reference was
changed, no framework/helper entered a bundle, and no feed URL, public key,
private key, Keychain entry, appcast, update request, download, or installation
was created. The current remote-dependency denial still applies.

The next implementation gate is a separately reviewed Sparkle integration:
relax the dependency policy for only the full pinned revision, inspect the
resolved source/license and complete embedded signed-code graph, inject an
unusable-by-default release configuration, and bind a testable runtime drain
gate before exposing a manual Check for Updates action. Real update evidence
then requires two notarized versions, clean physical upgrade/rollback failure
tests, active-Control denial, Agent reconciliation, and an externally signed
appcast/archive.

