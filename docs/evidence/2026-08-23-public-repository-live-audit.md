# Public repository live audit

Date: 2026-08-23

## Verified state

A read-only GitHub API inspection of
[`Jenny-Media/MacCompanion`](https://github.com/Jenny-Media/MacCompanion)
confirmed:

- visibility is public;
- `main` is the default branch;
- the live remote head is
  `cd3ad22bf0cab25638d31629b7ea28ad2a02961c`;
- GitHub detects no repository license;
- the repository is neither archived nor disabled;
- the `main` branch protection endpoint reports no protection;
- the repository has no rulesets;
- secret scanning, push protection, secret validity checks, non-provider
  patterns, and Dependabot security updates are disabled.

The clean local `main` head at the audit was
`ed98ddfb079cbc85f5b9a49d0465a1cab546a42d`, 74 commits ahead of the matching
local `origin/main` reference. The live GitHub head exactly matched that remote
reference. No fetch, push, setting change, issue, release, App Store record, or
other external mutation occurred.

The repository material gate passed immediately before this audit over 1,097
current files, 1,751 reachable historical blob paths, and 14 adversarial
fixtures. That is evidence about the local reachable history, not a substitute
for GitHub provider controls or legal approval.

## Publication hold

Do not push the 74 local commits until all of the following are complete:

1. Legal review approves Apache-2.0 adoption and the separate Mac
   Companion/Jenny Media trademark policy.
2. The approved `LICENSE`, trademark policy, `CONTRIBUTING.md`, and
   `SECURITY.md` are internally reviewed together so their grants, exclusions,
   contribution hold, and reporting route do not conflict.
3. GitHub private vulnerability reporting is enabled and its published route is
   tested from a non-administrator view.
4. Secret scanning, push protection, validity checks, and appropriate
   non-provider-pattern coverage are enabled before the next push.
5. A `main` ruleset or branch protection policy requires the public validation
   workflow, pull-request review, conversation resolution, code-owner review
   for release/security boundaries, and blocks force pushes and deletion.
6. The exact 74-commit range is re-scanned after the policy files are added;
   the staged diff, commit list, generated project, workflow permissions,
   release credentials boundary, and historical material report receive a
   human review.
7. One explicit publication confirmation names the exact local head and remote
   destination immediately before pushing.

Provider controls are external mutations and remain confirmation-gated. Legal
approval is not inferred from the selected license family. Until the hold is
cleared, local implementation, validation, evidence, and signed private-device
work may continue without publishing source.

## Recommended protection baseline

The first ruleset should target the default branch and:

- require a pull request and at least one approval;
- dismiss stale approvals after code changes;
- require code-owner review for owned paths;
- require conversation resolution;
- require the exact immutable public-CI check after its first successful remote
  run;
- block branch deletion and force pushes;
- apply to administrators except for a documented break-glass path; and
- avoid requiring an unproven signing or deployment check merely to make the
  policy look stricter.

Release tags and publication credentials need a separate protected release
lane. Branch protection alone does not authorize notarization, TestFlight,
App Store submission, Sparkle signing, or binary publication.
