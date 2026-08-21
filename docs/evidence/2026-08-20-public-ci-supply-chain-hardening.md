# Public CI supply-chain hardening evidence

Date: 2026-08-20

## Claim

The unsigned public workflow grants only read access, cannot publish, and no
longer resolves its checkout implementation through a movable major tag.
`actions/checkout` is pinned to the full verified v6.1.0 release commit
`d23441a48e516b6c34aea4fa41551a30e30af803`, and credential persistence is
disabled because the validation job never pushes.

Primary-source verification:

- [actions/checkout v6.1.0 release](https://github.com/actions/checkout/releases/tag/v6.1.0)
- [exact pinned commit](https://github.com/actions/checkout/commit/d23441a48e516b6c34aea4fa41551a30e30af803)

`scripts/validate_ci.py` scans every YAML workflow. Local repository actions are
allowed; remote GitHub actions require a full lowercase 40-character commit
SHA; container actions require a full SHA-256 digest. The validator runs before
Swift compilation in the same public entry point and fails with file, line,
reference, and a closed policy reason. The separate
[Swift dependency policy](2026-08-20-swift-dependency-policy.md) evaluates every
package manifest and denies remote packages and executable dependency surfaces
before the same compilation step.

The [repository material boundary](2026-08-20-repository-material-boundary.md)
also scans every tracked or publishable untracked file and every blob/path
reachable from local refs before compilation. It rejects high-confidence
secret/signing material, private database and credential file forms, unbounded
files, and repository-escaping current or historical symlinks without exempting
its adversarial fixture directory.

## Verification

The validator passes the current workflow. Direct policy cases prove rejection
of a movable action tag and mutable container tag, plus acceptance of a pinned
action commit, pinned container digest, and local action. The complete hardened
repository gate passes with 60 indexed protocol/product fixtures, 14 repository-
material fixtures, 12 dependency-policy fixtures, 12 privacy-manifest fixtures,
10 source-SBOM fixtures, 16 release-evidence fixtures, and 806 Swift tests.

## Remaining publication gates

This is CI construction evidence, not authorization to publish the repository.
The project still needs written license and trademark decisions, a private
vulnerability-reporting destination, maintainer ownership for `CODEOWNERS`,
protected-branch configuration, secret scanning, and push protection before
public launch. No signing, notarization, update, Apple-account, or pairing
secret belongs in this workflow.

## 2026-08-21 live remote audit

A read-only GitHub CLI audit found that `Jenny-Media/MacCompanion` is already
public. Its default branch is `main`; no repository ruleset or classic branch
protection exists; no Actions run is recorded; GitHub reports no repository
license; private vulnerability reporting is disabled; and secret scanning,
non-provider patterns, validity checks, and push protection are all disabled.
The published root currently contains only `.gitignore`, `README.md`, and
`docs`.

The local tree now includes `.github/CODEOWNERS`, assigning the sole visible
Jenny Media organization member and authenticated repository administrator
`@xcv58`, plus a contribution hold that prevents accepting external work before
the license, contribution terms, trademark policy, and private reporting route
are approved. These local files are not remote configuration and have not been
published. Branch protection, repository rules, security features, private
reporting, and any push remain explicit external writes requiring separate
authorization.
