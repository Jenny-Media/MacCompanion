# iOS physical-evidence profile v0.1

Status: normative for protected Mac Companion release tooling.

This canonical record closes the three iOS promotion scenarios without
performing them. It never installs, launches, scans, pairs, changes Local
Network permission, backgrounds an app, reconnects, invokes an operation, or
publishes a build.

The canonical `ios-physical-evidence.json` is at most 1 MiB and binds a fresh
installation on one passcode-protected arm64 iPhone/iPad, the exact clean
beta/stable source revision, official iOS bundle identifier, and exact
`iosArchive` from release evidence. Its three ordered cases require the exact
candidate version/build and distinct bounded observations:

- `physical-pairing` ends `pairedObserveAndActReady` only after local camera
  permission, QR expiry enforcement, host fingerprint pinning, SAS agreement
  on both devices, locally confirmed device naming, correct session and
  approval key custody, durable-before-visible pairing, one Observe status,
  and one explicitly approved and observed `setAudioMuted` operation.
- `local-network-denial` ends `localUIAvailableRemoteDeniedThenRecovered` only
  when denial publishes no route or broader authority, local recovery guidance
  remains available, a later Settings grant recovers the route, and the pinned
  host identity is unchanged.
- `background-reconnect` ends `foregroundPinnedReconnectReady` only after
  backgrounding closes Interactive Control, network loss retires the route,
  pre-first-unlock reconnect is denied, post-first-unlock session reconnect
  needs no presence prompt, foreground return revalidates the host pin, pending
  operations do not replay, and Control still requires fresh presence.

Each observation is a distinct relative file with non-placeholder SHA-256 and
positive size no greater than 16 MiB. Verification uses bounded,
descriptor-bound, no-follow reads and rejects hard links, path escape,
symlinks, mutation, unknown fields, missing/reordered assertions, case or
candidate substitution, duplicate evidence, and noncanonical record JSON.

For an iOS `promotionReady` manifest, `physical-pairing`,
`local-network-denial`, and `background-reconnect` must reference this same
record. File verification returns `invalidIOSPhysicalEvidence` for opaque,
divergent, malformed, stale, or candidate-mismatched evidence. Truthful device
capture, accessibility review, TestFlight/App Store evidence, and human
approval remain protected release responsibilities.
