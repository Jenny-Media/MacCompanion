# Protected per-architecture signature inspection execution

Date: 2026-08-22

## Claim

The protected signing collector can now execute the complete fixed
per-architecture inspection checkpoint after, and only after, the exact same
reconstructed object has passed the whole-subject Apple verification phase.
It composes independently derived embedded-signature facts, bounded Apple
display output, privately retained certificate files, and the independently
validated signing policy without making a platform-acceptance claim.

Before any per-architecture tool call, the executor rederives both fixed plan
sets from the graph and requires exact graph, policy, and numeric architecture
coverage. It then reopens every retained whole-subject stdout and stderr by
mode, owner, link count, byte count, and SHA-256; reparses the path-bound
success grammar; and requires the recorded before/after subject inventories to
equal a fresh reconstruction. Missing, reordered, failed, mutated, or merely
asserted prerequisite records stop the phase before inspection.

For every admitted architecture, the executor:

1. rehashes the complete reconstructed distribution subject;
2. independently inspects the exact graph-bound Mach-O slice and embedded
   signature;
3. proves the unique certificate prefix is unused;
4. runs the fixed identity, requirements, and certificate extraction command;
5. rehashes the complete subject and reopens both raw streams exactly;
6. inventories only contiguous `prefix0` through `prefix7` certificate files,
   opens each without following links, requires a single-link regular file
   owned by the release user and bounded to 1 MiB, removes group/world access,
   synchronizes mode `0600`, admits only root-bound platform provenance, and
   descriptor-hashes the stable bytes;
7. runs the fixed entitlement command and repeats complete-subject and raw
   output reinspection; and
8. requires embedded facts, Apple display facts, extracted leaf certificate,
   prior Apple verification, explicit-requirement evaluation, and every
   architecture policy field to agree exactly.

A failed identity command is never allowed to lend meaning to its output. If
it leaves a partial certificate file, the collector rejects the contaminated
phase. A clean failed invocation can be retained only as a typed failure with
no correlation or policy result. Every successful policy comparison still
contains `platformAcceptanceEligible: false`.

## Adversarial validation

`scripts/validate_platform_codesign_inspection_execution.py` exercises the
real reconstruction, plan derivation, raw-reference reinspection, private
certificate filesystem collector, and policy comparator with injected bounded
Apple-tool success output. It covers:

- complete multi-object and fat-architecture success while acceptance remains
  false;
- missing and failed whole-subject prerequisites;
- changed plans, mutated retained output, and subject mutation before any
  per-architecture invocation;
- graph/policy coverage drift and leaf-certificate policy substitution;
- pre-existing, noncontiguous, symlink, oversized, or writable certificate
  output;
- mode-`0600` conversion and exact retained certificate hashes; and
- a failed identity command both with and without forbidden partial
  certificate output.

The validation is part of `scripts/validate.sh`. The earlier embedded parser,
display grammar, fixed runner, subject reconstruction, and whole-subject
verification validators remain independent gates.

## Real Apple-tool compatibility probe

A read-only probe against an installed notarized third-party Developer ID app
then exercised the exact numeric architecture selector and corrected fixed
certificate option, `--extract-certificates=PREFIX`, through the pinned
`/usr/bin/codesign`. Real output confirmed that requirements are written to
stdout, display facts to stderr, signature size uses `Signature size=N`, the
display `Executable` is the selected bundle's main Mach-O, and certificate
files are contiguous `prefix0`, `prefix1`, and `prefix2` DER files initially
created mode `0644`.

The production certificate collector reopened those three real files without
following links, synchronized them to mode `0600`, and retained their exact
sizes and SHA-256 digests. The restricted workspace sandbox could not resolve
the external app's certificate authorities or emit certificate files, so this
compatibility probe ran through the explicitly authorized outside-sandbox
release-tool lane. It did not alter, launch, or resign the inspected app.

## Non-claims and next gate

The positive full executor fixture injects bounded tool output, and the real
tool probe used an unrelated installed app. Neither is a claim that a
production candidate or synthetic repository subject passed complete Apple
signature inspection. No certificate chain is checked into the repository.

Modern DER entitlement semantics remain deliberately rejected, and the
executor is therefore not yet acceptance-capable for signatures containing a
DER entitlement slot. Outer recursive bundle verification,
notarization/stapling/Gatekeeper correlation, canonical evidence publication,
the exported IPA lane, stable supported toolchain evidence, final credential
custody, and physical/promotion gates also remain open.

The later [semantic DER-entitlement equality checkpoint](2026-08-22-der-entitlement-semantic-equality.md)
supersedes only the DER limitation: matching XML-plus-DER signatures now pass
independent semantic correlation. DER-only remains outside v0.1, and every
outer, release, physical, and promotion gate above remains open.
