# Repository material policy v0

The public Mac Companion source tree contains code, specifications, synthetic
fixtures, and non-secret evidence only. The local validator examines every file
reported by Git as tracked or nonignored/untracked, plus every unique blob/path
reachable from every local ref, before compilation.

## Denied paths

- Private-key, certificate, provisioning-profile, and Apple API-key files
- Environment files other than `.env.example`
- SQLite/database files and directories conventionally named for secrets
- Symlinks that resolve outside the repository
- Files larger than the scanner's bounded eight-megabyte inspection limit

The same path, content, symlink, and size policies apply to reachable history.
A secret removed from the working tree remains a failure until the affected
history is deliberately remediated and any exposed credential is revoked.

## Denied content

- PEM private keys or certificates
- Recognizable live credential forms for GitHub, OpenAI, AWS, Slack, Stripe,
  and Google APIs
- Tracked Xcode development-team, explicit signing-identity, or provisioning-
  profile assignments

Adversarial fixtures encode their synthetic input as base64 in one JSON file.
The live scan therefore has no excluded fixture directory in which real material
could be hidden.

This scanner is a deterministic pre-commit/CI defense, not a complete secret-
detection system. Public repository launch still requires provider-side secret
scanning, push protection, history review, and credential revocation procedures.
