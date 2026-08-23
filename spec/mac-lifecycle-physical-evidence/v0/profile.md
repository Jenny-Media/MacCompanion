# Mac lifecycle physical-evidence profile v0.1

Status: normative for protected Mac Companion release tooling.

This canonical, candidate-bound record closes the four non-update macOS
promotion scenarios. It validates retained observations and never launches,
installs, revokes, unregisters, removes, mounts, signs, notarizes, or publishes.

The canonical JSON file is named
`mac-lifecycle-physical-evidence.json`, is at most 1 MiB, and binds one arm64
physical Mac, the exact clean beta/stable source revision, reviewed foreground
update-check profile, official app identity, and the exact application ZIP,
DMG, and Sparkle archive from release evidence.

## Exact cases

The ordered case set is closed:

- `quarantine-launch` requires the exact candidate running for a fresh user,
  with quarantine present, Gatekeeper acceptance, no bypass, and official
  identity observed.
- `clean-install` requires the exact candidate ready for a fresh user, with
  prior product state absent, explicit enablement, both login roles running,
  authenticated Agent readiness, and local administration available.
- `permission-revocation` requires the exact candidate locally manageable but
  remote-denied, with Screen Recording and Accessibility revoked, capture and
  input denied, remote ingress denied, local administration retained, and
  regrant requiring local action.
- `complete-uninstall` requires no observed version/build and product removed,
  after remote disablement, login-role unregistration, listener absence,
  pairing revocation, product-data removal, absence of privileged helpers, and
  proof that reinstall does not silently restore authority.

Each case retains one distinct relative evidence file with a non-placeholder
SHA-256 and positive size no greater than 16 MiB. Verification uses bounded,
descriptor-bound, no-follow reads and rejects hard links, path escape,
symlinks, mutation, unknown fields, missing/reordered assertions, case or
candidate substitution, duplicate evidence, and noncanonical record JSON.

For a macOS `promotionReady` manifest, `clean-install`,
`permission-revocation`, `complete-uninstall`, and `quarantine-launch` must all
reference this same record. File verification returns
`invalidMacLifecyclePhysicalEvidence` for opaque, divergent, malformed, stale,
or candidate-mismatched evidence. Truthful physical capture and human review
remain protected release-runner responsibilities.
