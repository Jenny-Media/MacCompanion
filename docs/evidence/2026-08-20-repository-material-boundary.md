# Repository material boundary

Date: 2026-08-20

## Claim

The unsigned public validation entry point now scans every Git-tracked and
nonignored/untracked repository file plus every unique blob/path reachable from
all local refs before dependency evaluation or compilation. It rejects
private-key, certificate, provisioning, Apple API-key,
environment, and database paths; secret-directory conventions; PEM private keys
or certificates; recognizable live credential forms for six provider classes;
and tracked Xcode team, signing-identity, or provisioning-profile assignments.
Symlink/path escape and files above the bounded eight-megabyte inspection limit
fail closed rather than being skipped.

The first live scan exposed unignored Python bytecode caches because the
compiled scanner contains its own test signatures. The repository now ignores
`__pycache__` and Python bytecode as generated tooling state. The resulting
inventory passes across 619 current source/evidence files and 34 historical
blob/paths.

## Verification

Fourteen indexed cases cover ordinary source plus encoded synthetic private
key, certificate, GitHub, OpenAI, AWS, Slack, Stripe, Google, Apple-key filename,
SQLite, environment, development-team, and provisioning-profile inputs. The
fixture content is base64-encoded in the indexed JSON; the live scanner excludes
no fixture directory where plaintext material could be hidden.

The validator reports path-scoped stable reasons and nonzero status. It runs in
`scripts/validate.sh` before SwiftPM manifest evaluation and compilation.
An isolated two-commit repository proved the historical boundary: after a
synthetic provider credential and outside-repository symlink were committed and
then deleted, the current-tree scan was empty while history validation still
reported both the credential and historical symlink escape.

## Boundary

This scanner recognizes high-confidence repository material and common live
credential shapes. It does not inspect ignored local secret stores, prove that
arbitrary high-entropy strings are harmless, or replace provider-side secret
scanning and push protection. Before publication, maintainers must still
perform a human history review, enable GitHub secret scanning and push
protection, and have a credential revocation process.
