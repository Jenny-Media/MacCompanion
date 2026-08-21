# Signed-code construction discovery

Date: 2026-08-21

## Claim

Signed-level file verification now requires one canonical, bounded,
descriptor-bound construction-discovery graph. The verifier independently
rediscovers every supported Mach-O regular member from the exact already
validated Mac application ZIP and iOS xcarchive, including objects that are
not declared release executables and objects without executable mode bits.

This is not Apple signature or release acceptance. Every symbolic tool step is
`notRun`, every artifact is `platformAcceptanceEligible: false`, and the valid
construction still yields `signedCodePlatformVerificationRequired`.

## Construction

- `spec/signed-code-graph/v0/profile.md` freezes the discovery and acceptance
  boundary.
- `scripts/signed_code_graph.py` hashes and inspects each archive through one
  stable `O_NOFOLLOW` descriptor, parses fixed bundle/Info.plist and
  LaunchAgent relationships, and parses thin/fat architecture and bounded
  load-command facts without extraction or Apple tool execution.
- `scripts/validate_release_evidence.py` requires exactly one passed
  `signed-code-graph-construction` validation record after artifact-SBOM
  validation. Its dedicated 4 MiB no-follow loader owns the reference check;
  the generic evidence stream cannot pre-read or follow this file.
- Per-executable signed-code construction records remain independently useful,
  but no v0.1 record can bypass graph validation. The graph is a separate
  acyclic release validation record rather than a self-reference in each
  executable bundle.

## Automated evidence

```text
validated 45 signed-code graph fixture(s)
validated 26 artifact-SBOM fixture(s)
validated 14 exact-candidate release-integration case(s)
validated 4 iOS/combined signed-code graph release-integration case(s)
validated 17 signed-code verification fixture(s)
validated 5 mac-packaging release-integration case(s)
```

The corpus contains a fat64 outer Mac executable, thin extensionless
LaunchAgent, fat32 versioned framework with no executable mode bit, iOS app,
extension, and framework, per-slice hashes, load-command/build-version and
code-signature-layout facts, bundle executable resolution, and a safe
BundleProgram edge. Adversarial cases cover omitted/invented objects, altered
architecture or plist facts, false platform/tool claims, stale roots,
malformed bundle/helper layouts, truncated/overlapping/duplicate-architecture
Mach-O containers, implicit bundle directories, ambiguous framework aliases,
duplicate plist keys, normal non-distribution dSYM companions, non-directory
ancestors, compression bombs, eager bundle-root bounds, duplicate release subjects, archive mutation and symlink
substitution, noncanonical/oversized/symlinked graphs, and release integration
without a graph or with an omitted nested framework.

## Remaining acceptance work

- Pin the final reviewed first-party/third-party identity, entitlement,
  architecture, and designated-requirement policy independently in release-job
  source after final target identifiers exist.
- Safely reconstruct the exact signed subjects and run fixed absolute Apple
  tools per object and architecture, treating `codesign --deep` only as an
  outer cross-check; correlate the retained raw outputs with the graph and
  policy, then revalidate all roots.
- Add the separately hashed exported IPA as the iOS acceptance artifact, prove
  sanitized provisioning/entitlements, and retain TestFlight/App Store and
  physical-install evidence.
- Repeat Mac Gatekeeper/notary/packaging evidence with stable Xcode 26.6, final
  signing custody, and the final directly distributed candidate.
