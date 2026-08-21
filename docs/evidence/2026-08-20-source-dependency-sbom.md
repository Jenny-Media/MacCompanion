# Source dependency SBOM construction

Date: 2026-08-20

## Claim

Mac Companion can now emit a deterministic SPDX 2.3 JSON document for its
closed release source graph. The document describes Mac Companion containing
the first-party `MacCompanionKit`, whose package dependency is explicitly
`NONE`. Generation first executes the live Swift dependency policy, which
denies remote packages, binary targets, and build-tool plugins. Repository-only
experiments remain outside the release component graph.

The generator binds product version, build, sorted release targets, full Git
revision, dirty state, explicit UTC creation time, generator identity, supplier,
and the exact dependency-policy digest into a UUIDv5 document namespace. It
writes deterministic sorted JSON with mode `0600`, fsyncs content and directory
entries, and publishes through an atomic no-clobber hard link. Two invocations
with reversed target arguments produced identical bytes and SHA-256
`277bceff133b8c1df4db4c9616ef1ba74f067c43d55bfdb7e9767753e4aa6475`.
Concurrent publication to one output produced exactly one success and one
closed `File exists` failure without a partial file.

`scripts/validate_sbom.py` enforces the project profile's exact document,
package, scope, and relationship boundary. Ten indexed fixtures cover the valid
graph and creator, file-analysis, license-assertion, namespace, relationship,
remote-component, scope, closure, and version-substitution failures. Timestamp
validation rejects impossible calendar values in addition to malformed text.

The existing unsigned release-evidence generator now uses the same atomic
no-clobber publication pattern. A freshly generated dual-target manifest still
passes release-evidence file verification.

## Standards basis

The profile follows the SPDX 2.3 document-creation, package-information, and
relationship fields, including `CC0-1.0` data licensing, a unique absolute
namespace, UTC creation time, supplier/component/version metadata, and
`DESCRIBES`/`CONTAINS` relations. SPDX 2.3 is selected for established JSON
tool compatibility; this does not claim it is the newest SPDX model.

## Boundary

This is intentionally a source dependency inventory. `filesAnalyzed` is false;
download location, project license, and copyright remain `NOASSERTION`; and no
artifact checksum is invented. The document labels itself as not being artifact
composition or license evidence. It therefore cannot satisfy the signed-
candidate SBOM gate alone. A release job must inspect and checksum the actual
built artifacts and retain separately reviewed dependency-license evidence.
The generated current-revision example is also dirty and is construction
evidence only.
