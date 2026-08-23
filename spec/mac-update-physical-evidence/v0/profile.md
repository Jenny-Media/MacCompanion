# Mac update physical-evidence profile v0.1

Status: normative for protected Mac Companion release tooling.

This profile records the signed old-to-new foreground update matrix required
before an external beta carries full update-check authority. It validates
retained evidence; it never launches an app, checks a feed, downloads,
installs, rolls back, mounts an image, signs, notarizes, or publishes.

## Closed record

The canonical UTF-8 JSON record is named
`mac-update-physical-evidence.json`, is at most 1 MiB, and contains exactly:

- schema `maccompanion.mac-update-physical-evidence.v0.1` and product
  `Mac Companion`;
- a whole-second UTC creation time;
- one bounded arm64 physical-Mac model and macOS version;
- the older signed source version/build, official bundle identifier, ten-byte
  signing Team ID, and a distinct hashed observation reference;
- the exact beta/stable candidate version, greater build number, clean source
  revision, official bundle identifier, reviewed foreground full-check
  profile, and exact `macApplication`, `macDiskImage`, and `sparkleArchive`
  artifact bindings from release evidence; and
- the following ordered, complete case set with exact terminal outcome,
  observed version/build, fresh-user state, and a distinct hashed observation:

| Case | Required terminal outcome | Version/build |
| --- | --- | --- |
| `not-now` | `sourceRunning` | source |
| `foreground-loss` | `sourceRunning` | source |
| `control-active-denial` | `sourceRunning` | source |
| `cleanup-uncertain-denial` | `sourceRunning` | source |
| `forced-loss-before-quiescence` | `sourceRunning` | source |
| `forced-loss-after-quiescence` | `sourceRecovered` | source |
| `forced-loss-after-agent-stop` | `sourceRecovered` | source |
| `successful-upgrade` | `candidateRunning` | candidate |
| `forced-loss-after-installer-handoff` | `candidateRunning` | candidate |
| `rollback` | `sourceRunning` | source |
| `clean-user-upgrade` | `candidateRunning` | candidate |
| `no-background-network` | `candidateRunning` | candidate |

Only `clean-user-upgrade` may set `freshUser=true`. The exact source and
candidate version/build observations prevent a generic "recovered" claim from
hiding which code is running. The source build must be numerically lower than
the candidate build.

## Evidence references

Every observation reference is a distinct, relative, bounded POSIX path with a
non-placeholder SHA-256 digest and a positive size no greater than 16 MiB.
File verification rejects missing files, symlinked path components, path
escape, size/hash mismatch, duplicate paths, malformed or noncanonical matrix
JSON, unknown fields, missing/extra/reordered cases, and every candidate or
outcome substitution.

The retained observation format may be text, canonical JSON, screenshot, or
other reviewable material. This v0.1 profile binds its bytes and terminal facts
but does not claim the observation is truthful. The protected physical runner
and human promotion approval remain responsible for trustworthy capture,
accessibility review, and interpreting the evidence.

## Release binding

For a macOS `promotionReady` claim, `upgrade` and `rollback` must reference the
same canonical `mac-update-physical-evidence.json`. Release file verification
parses the record, verifies every transitive observation, and binds the exact
candidate and three release artifacts. A missing, divergent, malformed, stale,
or information-only matrix returns `invalidMacUpdatePhysicalEvidence` and
cannot be repaired by an opaque passed scenario.

The broader release profile still separately requires clean install,
permission revocation, complete uninstall, quarantine launch, packaging,
signing, notarization, Sparkle publication, and human approval evidence.
