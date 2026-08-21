# Swift dependency policy evidence

Date: 2026-08-20

## Claim

Mac Companion's four current Swift packages form a closed, local-only graph.
The machine-readable policy lists every manifest by repository-relative path,
package name, SwiftPM identity, tools version, and exact local dependency. Both
network experiments and the platform-authority experiment depend only on the
in-repository `MacCompanionKit`; `MacCompanionKit` has no package dependency.
The third edge lets the disposable capture/encode smoke command exercise the
same production adapter code without making an experiment a release product.

`scripts/validate_dependency_policy.py` evaluates every discovered manifest
with `swift package dump-package` without resolving or fetching dependencies.
It fails on an added or missing manifest, package identity or tools-version
drift, missing or substituted local edges, a local path or symlink that escapes
the repository, any source-control or registry package, any binary target, or
any build-tool plugin target. While the policy denies remote dependencies, a
repository `Package.resolved` or Xcode remote-package reference is also a
failure so another project surface cannot bypass the manifest inventory.

The boundary is intentionally restrictive, not permanent. Introducing an
external package requires an explicit policy design that pins and verifies its
source and resolved revision before the denial may be relaxed. A lockfile alone
would not provide that authorization.

## Verification

Twelve indexed observations include the live valid topology and adversarial
cases for duplicate, added, or missing packages; package-name, identity, and
tools-version substitution; remote dependencies; local path escape; missing or
unexpected local edges; and executable external artifacts. Each invalid case
must produce its exact closed failure-code set.

The focused fixture-only and live-manifest commands pass. The dependency check
runs before compilation in `scripts/validate.sh`, so the unsigned public CI
entry point cannot compile a newly acquired package or executable build
extension before the policy has accepted it.

## Boundary

This proves dependency declaration closure at the checked revision. It does not
prove that first-party code is safe, audit the Apple SDK/toolchain, scan source
for vulnerabilities, or replace an SBOM and artifact inspection for a signed
candidate. The release evidence profile retains those separate gates.
