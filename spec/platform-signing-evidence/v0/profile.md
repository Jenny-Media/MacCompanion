# Mac Companion platform signing evidence profile v0.1

Status: normative design for a protected release-only collector. The public
repository does not yet contain an acceptance-capable collector, production
identity policy, or production policy digest.

This profile defines the evidence that must replace
`signedCodePlatformVerificationRequired`. It consumes one already validated
release manifest, exact-candidate artifact SBOM, signed-code graph, and
independently pinned signing policy. It cannot broaden any of those inputs.

## Execution authority

The collector runs only in an exclusive trusted release lane. The runner
supplies the signing-policy SHA-256 from protected configuration and records a
closed environment identity: host OS build, Xcode build, SDK build, and an
exact inventory of every executable tool by absolute path, byte count, and
SHA-256. Candidate-controlled `PATH`, shell startup files, aliases, plugins,
configuration files, environment variables, and executable search are not
authority.

Each invocation is an argv array for one approved absolute tool. The collector
never invokes a shell. It sets a closed environment, a bounded timeout, a
private mode-0700 working root, bounded stdout/stderr capture, and records the
exit status, termination reason, started/completed times, and hashes of the raw
outputs. Output truncation, timeout, signal termination, missing output,
unknown tool identity, or an unapproved argument shape fails closed.

## Exact subjects

The collector opens the already hashed artifacts through descriptors and
reconstructs every exact artifact-SBOM entry under each distribution subject,
including property lists, sealed resources, signature resources, embedded
provisioning material, nested bundles, and non-code files. The signed-code
graph selects executable verification subjects and traversal order; it never
filters the reconstructed bundle contents. Exact SBOM equality rejects unknown
archive members.

The reconstruction preserves only SBOM-listed safe relative symlinks, including
bounded standard versioned-framework chains. It does not follow links while
validating or creating their topology, and resolves the completed topology
separately inside the owned root. Absolute, escaping, missing, cyclic,
colliding, substituted, or unlisted links; hard links; special files; path
escapes; duplicate paths; writable contamination; and topology changes fail
closed. Bundle-root and standalone subjects come only from the graph; nested
code is inspected deepest-first. `codesign --deep` may be retained only as an
outer consistency check and never as discovery or repair.

Before and after every tool phase, the collector rehashes the release manifest,
SBOM set, graph, policy, artifacts, and reconstructed subjects. Any mutation
invalidates the run. Cleanup verifies the owned private root before removal;
ambiguous or contaminated recovery state is retained and reported rather than
force-deleted.

## Closed evidence

The canonical UTF-8 JSON record uses schema
`maccompanion.platform-signing-evidence.v0.1`, is at most 8 MiB, and binds:

- the exact release/source identity and SHA-256 references for the release
  manifest, artifact SBOM, signed-code graph, and signing policy;
- the closed environment and fixed-tool inventory;
- every artifact and reconstructed subject, including before/after digests;
- every invocation and its bounded raw-output references;
- every Mach-O object and architecture from the graph;
- parsed CodeDirectory digest and CDHash, signing identifier, Team ID,
  designated requirement data, certificate chain and validity result,
  timestamp result, hardened-runtime result, and exact sanitized entitlements;
- per-rule comparisons against the independently pinned policy; and
- target-specific platform results and explicit unresolved external gates.

The record contains public verification facts and sanitized provisioning
metadata only. Private keys, credentials, complete provisioning profiles,
authentication tokens, device secrets, and candidate-controlled policy are
forbidden.

## macOS acceptance

For each graph object and architecture, the collector retains fixed-tool
`codesign` verification and inspection evidence and proves all policy fields.
The `developerIDApplication` trust profile means all of the following, not
merely Team ID or leaf-digest equality:

- the Apple generic anchor evaluates successfully;
- the Developer ID Certification Authority marker
  `1.2.840.113635.100.6.2.6` exists on the issuing certificate;
- the Developer ID Application marker
  `1.2.840.113635.100.6.1.13` exists on the leaf;
- the leaf subject organizational unit equals the independently pinned Team
  ID; and
- the signing identifier equals policy and the embedded designated-requirement
  bytes hash exactly to `designatedRequirementDataSHA256`.

The fixed invocation is the following shell-free argv array after replacing
`TEAM_ID` with the independently pinned policy value and `SUBJECT` with the
owned reconstructed path:

```text
[
  "/usr/bin/codesign",
  "--verify",
  "--strict",
  "--all-architectures",
  "--verbose=4",
  "--test-requirement",
  "=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"TEAM_ID\"",
  "SUBJECT"
]
```

The leading `=` makes the option value literal requirement source rather than
a requirement file path. The collector serializes the expression with no
candidate-controlled fragments. Exit zero is necessary; timeout, signal,
truncation, nonzero exit, warning-only substitution, or missing retained raw
stdout/stderr fails. Separate per-architecture inspection and policy comparison
is still required, and embedded designated-requirement digest equality remains
independent of the external test-requirement result.

With the fixed `LANG=C` and `LC_ALL=C` environment, verification success has a
closed output grammar. Stdout is empty. Stderr is exactly these three UTF-8,
LF-terminated lines, where `SUBJECT` is the exact owned argv path:

```text
SUBJECT: valid on disk
SUBJECT: satisfies its Designated Requirement
SUBJECT: explicit requirement satisfied
```

Missing, reordered, additional, warning, wrong-path, CRLF, undecodable, or
otherwise unrecognized output fails closed even after exit zero. A supported
stable-toolchain change to this grammar requires new measured evidence and a
profile revision before acceptance; it is not tolerated as an open parser.

For the final application and disk image it additionally retains Gatekeeper
assessment, accepted notarization correlation, and stapling validation against
the exact candidate. Packaging-equivalence platform verification must already
pass for the same hashes. A recursive outer verification does not excuse a
missing per-object result.

## iOS construction boundary

An xcarchive-only result remains construction evidence. iOS platform acceptance
requires Xcode export through a separately specified protected lane, a distinct
artifact-SBOM entry for the exact exported IPA, sanitized provisioning and
distribution identity inspection for every contained executable, and physical
installation/launch evidence. Until that exported-artifact profile exists and
passes, the collector records `iosArchiveConstructionOnly` and cannot clear the
platform gate.

## Acceptance and remaining gates

A record is acceptance-eligible only when every input digest, object,
architecture, policy rule, invocation, raw reference, and target-specific
result is present and passed. Unknown or extra objects, partial success,
warnings treated as success, schema-only records, beta-toolchain evidence, or
synthetic identities are non-acceptance evidence.

Even a valid record cannot substitute for stable supported Xcode/macOS,
production certificate custody, final identifiers and entitlements, physical
device matrices, notarization/App Store state, or human promotion approval.
The release-evidence validator must continue returning
`signedCodePlatformVerificationRequired` until a separate implementation and
adversarial corpus enforce this profile and the release lane supplies all
external gates.
