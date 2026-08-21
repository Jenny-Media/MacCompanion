# Mac packaging equivalence profile v0.1

Status: normative for repository release tooling.

This profile proves that the finalized Mac application ZIP, Sparkle archive,
and disk image carry one identical `Mac Companion.app` payload. It complements
the exact-candidate artifact SBOM and does not prove signing, notarization,
stapling, Gatekeeper acceptance, licenses, or promotion readiness.

The release lane is a trusted, single-owner execution environment. Untrusted
code and concurrent processes running as the release UID are excluded while
candidate artifacts and evidence are inspected or published; Unix modes on a
same-owner temporary directory are privacy and accident boundaries, not a
defense against a compromised peer with that UID. Receipts are content-addressed
construction records. The independent release verifier must revalidate every
referenced candidate immediately before acceptance.

## Evidence receipt

The canonical UTF-8 JSON receipt is named
`mac-packaging-equivalence.json`. It binds:

- product, release version/build/target, clean source revision, and generation
  time;
- the exact artifact-SBOM index reference;
- the canonical app name, tree SHA-256, entry count, and expanded bytes;
- exactly one `macApplication`, `sparkleArchive`, and `macDiskImage` artifact,
  including each release ID/path/hash/size and identical app-tree summary; and
- the exact read-only APFS DMG root layout.

The receipt is bounded to 1 MiB. The canonical app tree is compact sorted-key JSON over every container-root-
relative directory, regular file, and symlink entry. Paths include the
`Mac Companion.app` root prefix and use the artifact-composition fields: path,
type, four-digit mode, bytes, SHA-1, SHA-256, and symlink target. The SHA-256
input includes the canonical JSON trailing newline. Timestamps, UID, and GID
are deliberately excluded. Any modeled difference changes the tree digest and
fails equivalence. Every non-root entry must name an explicit parent entry of
type `directory`; implicit or orphaned directory structure is rejected.

Both ZIPs contain only one top-level `Mac Companion.app`. The DMG root contains
exactly `Mac Companion.app` and `Applications -> /Applications`. v0.1 rejects
styled backgrounds, `.DS_Store`, volume icons, installers, scripts, second
apps, and every other root entry.

## DMG inspection

Routine public validation never mounts images. The explicit generator and
release verification path require `--allow-readonly-mount` or the equivalent
release-only flag. Inspection:

1. binds and hashes the exact non-symlink DMG;
2. runs noninteractive UDIF verification and rejects encrypted or non-UDZO
   images;
3. attaches one APFS volume read-only at a private mode-0700 mount point with
   browsing and auto-open disabled;
4. accepts only the frozen root layout and scans with `lstat`, no-follow opens,
   same-device checks, streamed hashes, and no symlink traversal;
5. rejects special files, regular-file hard links, file flags, case/NFC
   collisions, unsafe app symlinks, and every extended attribute except the
   system-managed `com.apple.provenance` in the current bounded 11-byte format
   with prefix `01 02 00`; that attribute is deliberately excluded from the
   tree model because current macOS adds it to locally created files and does
   not allow the release process to remove it; every other name, length, or
   prefix fails closed, and v0.1 does not claim a separate macOS ACL
   attestation;
6. snapshots existing image devices and persists a private recovery record
   before attach, then detaches only the exact new device correlated through
   this invocation's private mount point;
7. requires confirmed unmount, device disappearance, and an unchanged DMG hash
   before removing that recovery record or publishing; and
8. publishes canonical mode-0600 evidence atomically without overwrite.

Unexpected tool output, timeout, cancellation, attach/mount mismatch, scan
failure, detach failure, or mutation observed by any bounded generator check
yields no receipt. The generator cannot make candidate paths and receipt
publication one filesystem transaction, so its output alone is never acceptance
evidence; the release verifier repeats archive, reference, and platform checks. A
SIGKILL or machine failure cannot be cleaned up in process; the trusted release
runner retains the exact image/device/run/prior-device record. The explicit
`scripts/reconcile_mac_packaging_recovery.py --allow-nonforce-detach` command
validates that record, the private pinned image, exact owned device, mount point,
and read-only volume facts before detaching without force or cleaning anything.

## Release binding

The existing release-evidence `validation` array carries one passed record with
ID `mac-packaging-equivalence`. Signed macOS file verification parses and
cross-binds that receipt to the release manifest and artifact SBOM. Absence
returns `missingMacPackagingEquivalence`; malformed, mismatched, or failed
platform reinspection returns `invalidMacPackagingEquivalence`.

The file verifier continues to fail closed unless the caller explicitly enables
read-only platform packaging verification; an otherwise valid receipt returns
`macPackagingEquivalencePlatformVerificationRequired` until then. Schema-only
examples are not release claims. `scripts/create_mac_packaging_equivalence.py`
is the explicit generator, and `scripts/validate_mac_packaging_equivalence.py`
owns the attach-free corpus plus the separately requested synthetic platform
integration.

The generator and receipt validator accept only an artifact-SBOM bundle and
release manifest that their respective conformance validators have already
accepted. Their integrated CLI and release-verifier entry points own that
precondition and normalize any subsequent receipt, filesystem, or tool failure
to a failed packaging-equivalence result.
