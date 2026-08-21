# Mac packaging-equivalence construction

Date: 2026-08-21

## Claim

The repository can now prove that the exact macOS application ZIP, Sparkle
archive, and APFS/UDZO disk image contain one modeled `Mac Companion.app` tree.
The proof is bound to the release version/build/targets, clean source revision,
exact artifact-SBOM index, and sole release artifact of each required Mac kind.

This is construction evidence, not a signed-candidate claim. No signed app,
notarized disk image, Sparkle signature, final bundle identity, or promotion
record was produced.

## Construction

- `spec/mac-packaging-equivalence/v0/profile.md` freezes the canonical receipt,
  app-tree coordinate system, exact three-container binding, and two-entry DMG
  root layout.
- `scripts/mac_packaging_equivalence.py` validates the closed canonical receipt,
  exact release/artifact-SBOM reciprocity, and identical ZIP/DMG trees. Its DMG
  path requires explicit authorization and the expected release hash/size.
- DMG inspection copies the already-hashed open release descriptor into a
  private mode-0400 snapshot, makes every disk-image tool consume only that
  path, verifies an unencrypted UDZO, snapshots existing disk-image devices,
  writes a private mode-0600 recovery record before attach, uses a
  private mode-0700 mount with browsing, auto-open, verification caching, and
  automatic filesystem checking disabled, and requires one read-only APFS
  volume. It rejects unexpected root entries, extra mounts, unsafe links,
  special files, hard links, file flags, path collisions, and unmodeled xattrs.
- `com.apple.provenance` is the sole excluded xattr, and only its observed
  bounded 11-byte `01 02 00`-prefixed form is accepted, because macOS 27 adds
  it to locally created files and does not allow this release process to remove
  it. Every other xattr name or shape fails closed. No separate ACL attestation
  is claimed by v0.1.
- Cleanup detaches only the exact newly owned root device, never force-detaches,
  confirms both unmount and disappearance from the image inventory, rehashes
  the DMG, and removes the recovery record only after clean closure. A cleanup
  failure retains the private record and mount path for trusted-runner
  reconciliation and publishes no receipt.
- `scripts/reconcile_mac_packaging_recovery.py` validates the exact private
  root, canonical record/run identity, prior device set, pinned hash/size/mode,
  owned device, and read-only APFS facts before an explicitly authorized
  non-force detach and cleanup. It refuses ambiguous or mutated state.
- `scripts/create_mac_packaging_equivalence.py` validates the exact archives,
  inspects the exact DMG, revalidates the completed receipt, and atomically
  publishes canonical mode-0600 evidence without overwrite.
- `scripts/validate_release_evidence.py --verify-files
  --verify-platform-packaging` parses and cross-binds the receipt, reinspects
  the DMG, reruns exact archive verification, and rehashes the receipt, index,
  archives, and DMG after platform work. Missing evidence, invalid evidence,
  and omitted platform authorization are distinct fail-closed results.

## Automated evidence

The attach-free public path passed:

```text
validated 24 mac-packaging-equivalence fixture(s)
validated 8 mounted-tree/xattr-policy case(s) without mounting a disk image
validated 5 mac-packaging release-integration case(s)
validated 3 partial-attach/recovery case(s)
validated 6 fail-closed recovery-refusal case(s)
validated 2 interrupted recovery-record update case(s)
validated one concurrent public-path substitution case against the pinned DMG copy
```

The corpus covers macOS-only and combined macOS/iOS releases, byte-identical
generation, closed schema/type/time/source/target/reference/container/layout
failures, a 1 MiB receipt bound, explicit parent-directory closure, canonical
and duplicate-key parsing, Unicode failure, payload and
layout substitution, duplicate/missing artifact kinds, mode-0600 no-overwrite
publication, missing versus invalid release evidence, and cleanup after both
malformed attach output, timeout after attachment, and repeated inventory
failure followed by the explicit recovery command. Mutated pinned bytes,
ambiguous image ownership, and a writable attachment are refused without
detach or evidence deletion. A valid primary recovery record remains executable
when a killed update leaves a zero-byte or truncated temporary sibling; two
valid records must agree on every immutable fact. Unexpected files, dangling
symlinks, and wrong entry types are refused before any detach. Public-path
substitution is rejected while every disk-image tool remains bound to the
private snapshot.

The mode-0700 private root does not defend against a compromised process with
the same release UID. This construction requires an exclusive trusted release
lane, and the generator's content-addressed receipt is not acceptance by
itself; the independent release verifier repeats the candidate checks.

One explicit synthetic platform integration also passed on macOS 27.0
(`26A5416b`) with Xcode 27.0 beta (`27A5218g`):

```text
validated 2 explicit APFS/UDZO packaging-reinspection case(s)
```

Those cases created only a temporary fixture app and disk image, ran the
production receipt generator and then the independent packaging branch of the
release file/platform verifier, mounted separate pinned copies read-only without
browsing or auto-open, verified exact tree equality, reran archive and
reference checks after platform work, rejected later DMG mutation, detached
each invocation-owned image without force, and removed the temporary state.
The release verifier still returned the independent
`signedCodePlatformVerificationRequired` gate, so this is not a complete
signed-candidate acceptance claim.

## Remaining evidence

- Run the same platform path on the stable macOS 26/Xcode 26.6 release runner.
- Generate and verify the receipt from the final signed, notarized candidate.
- Capture and freeze real macOS 26 tool-output compatibility evidence; macOS 27
  deprecates these `hdiutil` operations, so a separately tested `diskutil image`
  backend is required before macOS 27 becomes a supported release baseline.
- Pin an independent SPDX 2.3 validator, bind signed-code verification bundles
  to exact executable-member digests, retain reviewed licenses, and complete
  physical/promotion evidence.
