# Mac Companion platform notarization evidence v0.1

Status: construction profile. It defines the exact evidence needed from two
Apple notary submissions but does not authorize a submission, staple an item,
or promote a release.

## Why there are two submissions

Mac Companion distributes a ZIP/Sparkle application archive and a DMG whose
mounted application trees must be identical. Apple's documented custom
workflow creates tickets for a submitted top-level container and nested code,
but a ZIP cannot itself be stapled. The application must therefore be
notarized through a transient ZIP and then stapled before the final application
archives and DMG are constructed. The final DMG is subsequently notarized and
stapled as a distinct byte transition.

The two ordered phases are:

1. `applicationArchive`: a transient `.zip` at
   `beforeApplicationStaple`, correlated to `mac-app`.
2. `diskImage`: the final-content `.dmg` at `beforeDiskImageStaple`,
   correlated to `mac-dmg`.

The submission UUIDs must differ. The disk-image submission must be created
after the accepted application log, preventing a pre-stapled or independently
constructed DMG from satisfying the order.

Apple documents that the submission name and SHA-256 identify the exact bytes
prepared for notarization, that completed status must be checked, and that the
developer log must be reviewed even after acceptance:

- <https://developer.apple.com/documentation/notaryapi/submitting-software-for-notarization-over-the-web>
- <https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>

## Accepted phase correlation

Each phase binds:

- one bounded upload filename, byte count, and non-placeholder SHA-256;
- one lowercased submission UUID;
- the exact bounded raw `notarytool info --output-format json` bytes and their
  private evidence reference;
- the exact bounded raw developer-log JSON bytes and their private evidence
  reference;
- exact matching filename, UUID, and upload SHA-256 across those records;
- `Accepted`, status code `0`, and `Ready for distribution`;
- zero errors or warnings; and
- a nonempty bounded ticket set.

Unknown top-level fields, duplicate JSON keys, malformed times, changed upload
hashes, reused submission IDs, warnings, reversed ordering, or attempted
acceptance promotion fail closed. Ticket contents remain inside the hashed raw
log because their shape is Apple-owned; v0.1 requires only a bounded nonempty
array of nonempty objects and makes no per-ticket semantic claim.

## Canonical record

The canonical record uses schema
`maccompanion.platform-notarization-evidence.v0.1`, is bounded to 4 MiB, and
binds a clean macOS-only release/source projection plus exactly the two phases.
It is deterministically recomposed from the raw inputs. Both phase records and
the root retain `platformAcceptanceEligible: false`.

## Remaining byte transitions

An accepted two-phase record does not yet prove a releasable candidate. The
following gates remain explicit:

- staple and rehash the application after the first acceptance;
- construct both final ZIPs and the final-content DMG from that stapled tree;
- submit the exact pre-staple DMG and staple/rehash it after acceptance;
- correlate the final release manifest and artifact SBOM to those post-staple
  bytes;
- validate both final app and DMG tickets and Gatekeeper assessments;
- repeat packaging equivalence against the final stapled DMG;
- use the stable release toolchain and controlled production credentials; and
- pass physical, human-promotion, and publication gates.

Actual `notarytool submit`, `stapler staple`, and Apple-account access are
external mutations and require explicit release authorization. Credential
names, passwords, API keys, session material, and temporary upload credentials
never enter this record or the repository.

