# Apple privacy-manifest boundary

Date: 2026-08-20

## Claim

Mac Companion now has a closed, machine-checked Apple privacy-manifest profile
for its three planned executable bundles. The iOS app template declares no
tracking, tracking domains, collected data, or required-reason APIs. The Mac
containing-app and Agent-service templates declare no tracking, tracking
domains, or collected data, and intentionally omit the required-reason key.

This is a source and candidate-resource claim, not built-bundle or App Store
evidence. Permanent Apple targets do not exist yet. Each final executable must
copy its indexed `PrivacyInfo.xcprivacy` to Apple's required bundle location,
and signed-candidate validation must inspect the resulting bundles.

## Primary-source basis

Apple documents the manifest structure and the distinction between collected
data, tracking, tracking domains, and required-reason APIs in [Privacy manifest
files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).
Apple's current required-reason API documentation lists iOS, iPadOS, tvOS,
visionOS, and watchOS, but not macOS, and requires approved reasons for covered
API categories on those platforms. Apple's App Privacy guidance defines
collection around data transmitted off-device in a way the developer or a
third party can access beyond servicing a request in real time. Mac Companion's
no-relay/no-analytics design gives Jenny Media LLC and third parties no such
access, so the current developer-collection assessment is false.

The approved-reason catalog and platform requirements can change. The policy
records the review date and requires a fresh primary-source review before App
Store submission or after any relevant platform, data-flow, dependency, API,
or target-topology change.

## Verification

`scripts/validate_privacy_manifests.py` performs five independent checks:

1. It rejects duplicate JSON and plist keys and enforces closed policy and
   manifest schemas.
2. It requires tracking false plus empty tracking-domain and collected-data
   arrays for every template.
3. It validates exact required-reason category/reason dictionaries against the
   current Apple catalog and requires the iOS key while forbidding it from the
   present Mac templates.
4. It scans every Swift source for covered uptime, disk-space, timestamp,
   keyboard, and user-default API forms and compares exact path/API/category/
   count records with the normative inventory.
5. It evaluates the live SwiftPM graph. A covered call reachable from either
   iOS entry target fails unless the entire source file is excluded by a
   whole-file `#if os(macOS)` guard.

Twelve indexed plist fixtures prove valid iOS/Mac forms and rejection of
collection, tracking, domains, missing/extra keys, duplicate XML keys,
duplicate categories, invalid reason codes, and SDK-only reason codes that are
not valid for these app-owned bundles. The live inventory currently
contains six records: Agent and Host `systemUptime`, Host `systemSize` and
`systemFreeSize`, and Persistence `stat`/`fstat`. The shared Persistence module
is reachable from the client UI but its file is wholly macOS-guarded; the
unguarded Agent occurrence is outside the iOS closure.

The validator runs in `scripts/validate.sh` before Swift compilation.

## Boundary

Static token inventory is deliberately conservative and cannot prove runtime
data practice. It also does not prove Xcode resource membership, built-bundle
placement, archive aggregation, App Store Connect answers, or Apple review.
Those remain signed-target and promotion evidence. Third-party SDK admission is
currently denied by the separate dependency policy; relaxing it requires both
supply-chain and privacy-manifest review.
