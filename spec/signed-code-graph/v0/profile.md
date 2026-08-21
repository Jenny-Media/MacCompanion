# Signed-code construction-discovery graph v0.1

Status: normative for bundle-independent construction discovery. It is not a
signed-candidate acceptance profile and it does not authorize signing policy.

The graph proves which Mach-O-bearing regular members exist in the exact
artifact-SBOM archives, how fixed Apple bundle layouts and LaunchAgent metadata
relate those members, and which per-architecture Apple checks a release-only
collector must later perform. It never executes a tool and every planned step
has status `notRun`.

## Canonical graph

The canonical UTF-8 JSON document uses schema
`maccompanion.signed-code-graph.v0.1`, evidence level
`constructionDiscovery`, and collector profile
`maccompanion.code-object-discovery.v0.1`. It is bounded to 4 MiB, rejects
duplicate or noncanonical JSON, and is read once through `O_NOFOLLOW`.

The closed root binds the product, full release, clean source revision,
generation time, exact artifact-SBOM index reference, and a path-sorted record
for every `macApplication` and `iosArchive`. Sparkle is already required to
have composition identical to the canonical Mac application and therefore is
not scanned as a second inventory authority.

Each artifact record binds all six artifact fields and records:

- exactly one distribution subject: the outer Mac `.app`, or the one
  `Products/Applications/*.app` product in the xcarchive;
- every fixed-suffix `.app`, `.framework`, `.appex`, `.xpc`, and `.bundle`
  root derived from all member-path prefixes under that subject, whether or
  not the ZIP carries an explicit directory entry, its closest enclosing bundle, one bounded
  parsed Info.plist reference, bundle identifier/package type/executable, and
  the executable path resolved from the supported Mac, versioned-framework,
  or flat iOS layout;
- every regular archive member whose first four bytes are a supported thin,
  fat32, or fat64 Mach-O magic, regardless of name, suffix, or executable bit;
- all seven exact composition fields for each discovered member, bundle owner,
  main-executable relationship, distribution-subject status, and any exact
  declared release-executable IDs;
- each Mac `Contents/Library/LaunchAgents/*.plist` Label and safe relative
  BundleProgram edge to an independently discovered Mach-O member; and
- a typed, shell-free symbolic verification plan using fixed tool/action IDs,
  bundle-root subjects for bundle main executables, standalone member subjects,
  and numeric CPU selectors. All steps are `notRun`.

The current iOS subject is explicitly an xcarchive product. It is always
`platformAcceptanceEligible: false`; a separately hashed exported IPA is
required before TestFlight/App Store or physical-install acceptance.

## Descriptor and parser invariants

Generation and validation open each ZIP with `O_NOFOLLOW`, require one regular
single-link file, hash it, reject zero-size compressed members and compression
ratios above the artifact profile before decompression, inspect every actual ZIP member through a duplicate
of the same descriptor, require the resulting type/mode/size/SHA-1/SHA-256 and
symlink facts to equal the artifact composition exactly, hash it again, and
require unchanged descriptor and public-path identity. No member is extracted
and no member path becomes a host path.

Thin parsing is bounded by the exact member or fat-slice size. Fat parsing
requires 1–16 nonempty, aligned, in-range, nonoverlapping slices; unique numeric
CPU type/subtype pairs; and agreement between each fat table entry and its thin
header. Every slice records offset, byte count, SHA-256, endianness, bit width,
file type, flags, load-command count/size, build/minimum-OS records, and
code-signature range presence. Load commands must be aligned, fully bounded,
and sum exactly to `sizeofcmds`; multiple or out-of-range code-signature
commands are refused. Code-signature presence is construction layout only, not
signature validity.

Before materializing the graph or symbolic plan, each artifact is capped at
256 bundle roots, 1,024 Mach-O objects, 2,048 aggregate architecture slices,
eight version records per slice, 4,096 aggregate version records, and 8,192
verification steps. Binary plist inspection rejects aliased offsets and
overlapping object extents, caps aggregate dictionary-key work at 4,096,
individual decoded keys at 1,024 bytes, and aggregate decoded key bytes at
256 KiB. The finished canonical graph must also fit its
4 MiB file bound. These are fixed release-profile ceilings rather than caller
claims.

Implicit ancestors are allowed, but any ancestor that is present as a ZIP
member must be a directory; a regular file or symlink can never also contain
children. Bundle discovery is deterministic for the supported layouts. Every modeled
bundle must have exactly one authoritative Info.plist, strict XML or binary
dictionary parsing rejects duplicate keys, and required string facts,
and a `CFBundleExecutable` that resolves to a discovered Mach-O unless it is a
non-code resource bundle. Unknown layouts do not remove Mach-O members from the
inventory, but this profile does not claim they have a valid Apple signing
topology.

## Acceptance boundary

This graph does not establish a Team ID, certificate, designated requirement,
CDHash, entitlement, notarization, Gatekeeper result, provisioning result, or
outer seal. It contains no allowlist or caller-supplied completeness assertion,
and it does not embed a policy that could authorize itself.

Future platform acceptance must independently pin the reviewed identity,
entitlement, architecture, and third-party-code policy in release-job source;
safely reconstruct the exact already validated subject; execute absolute Apple
tools without a shell or `PATH`; capture the tool/OS identity and raw output;
check every object and architecture deepest-first; treat `codesign --deep` only
as an outer cross-check; apply Gatekeeper only to the outer Mac app; correlate
iOS provisioning with signed entitlements; and revalidate all archive, graph,
policy, and output bytes before opening `signedCandidate`.

## Validator and fixtures

`scripts/signed_code_graph.py` owns descriptor-bound discovery and exact graph
recomputation. `scripts/validate_signed_code_graph.py` owns the indexed corpus.
The corpus includes Mac outer app, extensionless LaunchAgent, versioned
framework, fat32/fat64 and thin arm64/x86_64 objects, iOS app/extension/framework,
an undeclared non-executable-bit Mach-O, per-slice construction facts, and
adversarial omission, invention, metadata, bundle, helper, fat-range,
duplicate-architecture, duplicate-release-subject, archive identity,
canonicalization, symlink, and size cases.
