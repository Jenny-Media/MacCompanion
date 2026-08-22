# Two-phase notarization correlation construction

Date: 2026-08-22

Status: deterministic non-acceptance construction evidence. No Mac Companion
artifact was uploaded, stapled, mutated, or promoted.

## Finding

The prior release-evidence shape assumed one notarization submission could
truthfully cover both a stapled application archive and a stapled DMG. That is
not compatible with the intended identical-tree release pipeline.

Apple documents that ZIP files cannot be stapled directly: the application is
stapled after its archive is accepted and a new ZIP is then constructed. Mac
Companion must therefore use two ordered submissions:

1. notarize a transient application ZIP and staple the application;
2. construct the final archives and DMG from that stapled application, then
   notarize and staple the DMG.

The release manifest now requires a hashed canonical two-phase evidence record
and two distinct accepted submission IDs instead of one uncorrelated receipt.

## Construction

`platform_notarization.py` defines the bounded
`maccompanion.platform-notarization-evidence.v0.1` record. Each phase requires
exact filename, byte count, SHA-256, UUID, raw `notarytool info` JSON, and raw
developer-log JSON. The parser requires:

- `Accepted` from both independently retrieved records;
- exact UUID, filename, and upload-hash correlation;
- status code `0` and `Ready for distribution`;
- no reported issue, including warnings;
- a nonempty bounded ticket set;
- application acceptance before DMG submission; and
- distinct submission IDs.

Duplicate JSON keys, unknown top-level fields, malformed time or UUID, upload
substitution, warning output, phase reuse/reordering, removed gates, and any
attempt to set `platformAcceptanceEligible: true` fail closed. Raw records are
retained only by bounded relative path, byte count, and SHA-256. Apple-account
and credential material is excluded.

## Verification

```text
python3 scripts/validate_platform_notarization.py
python3 scripts/validate_release_evidence.py
```

The validators cover both accepted phases, exact recomposition, upload-hash
substitution, warning rejection, unknown and duplicate keys, one-submission
release-manifest rejection, reused UUIDs, temporal reversal, oversized raw
evidence, removed gates, phase swapping, and attempted acceptance promotion.
Both validators are part of `scripts/validate.sh`.

## Remaining boundary

This checkpoint does not execute `notarytool`, measure the current successful
Apple JSON against a Mac Companion submission, staple or rehash the application
or DMG, build the post-application-staple archives, correlate the final release
artifacts to their pre-staple uploads, assess the final DMG with Gatekeeper,
repeat packaging equivalence, use stable Xcode 26.6, or clear a release,
physical, or promotion gate. Those mutations require an explicitly authorized
release run.

