# Open-source policy bundle checkpoint

Date: 2026-08-23

## Outcome

The local repository now contains the publication-policy files selected by the
approved design:

- the byte-exact official Apache License 2.0 text in root `LICENSE`;
- a project `NOTICE` naming Jenny Media LLC and pointing to the separate brand
  terms;
- a draft `TRADEMARKS.md` that permits accurate descriptive references while
  requiring public forks to use distinct product, bundle, signing, update,
  website, and store identities;
- a truthful `SECURITY.md` that identifies GitHub private vulnerability
  reporting as the intended route but explicitly says it is not operational
  until enabled and verified;
- an updated `CONTRIBUTING.md` that keeps intake closed and records the intended
  Developer Certificate of Origin 1.1 policy without soliciting sign-offs; and
- a `CODE_OF_CONDUCT.md` that fixes conduct expectations while acknowledging
  that a private enforcement route and responsible maintainer are not yet
  published.

The README links the complete bundle. `scripts/validate_open_source_policy.py`
is part of the ordinary validation gate. It requires regular single-link
bounded files, the official Apache license SHA-256
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`,
the contribution hold, non-operational private-reporting truth, fork identity
separation, safe-reporting instructions, and the cross-file links.

## Source verification

The root license was compared byte-for-byte with the Apache Software
Foundation's official text at
<https://www.apache.org/licenses/LICENSE-2.0.txt>. The surrounding structure was
checked against ASF guidance for applying Apache-2.0, the official Developer
Certificate of Origin 1.1, and GitHub's current documentation for security
policies, private vulnerability reporting, and community health files:

- <https://www.apache.org/legal/apply-license>
- <https://developercertificate.org/>
- <https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy>
- <https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately>
- <https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories>

These sources do not replace Jenny Media's written legal review.

## Authority retained

This checkpoint is local-only. It does not:

- claim that trademark clearance or legal review passed;
- enable GitHub private vulnerability reporting, secret scanning, push
  protection, rulesets, branch protection, or Dependabot;
- open contribution or external security-testing intake;
- publish the policy bundle or push any commit;
- authorize use of official Jenny Media signing, Apple identifiers,
  entitlements, update channels, or branding by forks; or
- create a supported external release.

The existing publication hold remains. The next repository-readiness proofs are
written legal approval, an exact-history/staged-range review at the eventual
publication head, enabled and non-administrator-verified private reporting,
provider protections, and immediate exact-head confirmation before any push.
