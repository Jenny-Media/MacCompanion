# Permanent Mac containing-app target evidence

Date: 2026-08-21

Status: provisional target and signing proof on Xcode 27 beta; not a release candidate

## Scope

The first permanent Apple target began as the visible Mac containing app. It
uses the registered `media.jenny.maccompanion` identifier and the package-owned
Mac dashboard. The project now also embeds the separately signed but inert
[permanent Agent target](2026-08-21-permanent-embedded-mac-agent-target.md).
Until the authenticated local client, complete Agent bootstrap, and status
capability are instantiated, the dashboard truthfully presents the Agent as
unavailable. Neither target listens remotely, starts capture or input, or
claims product readiness.

`project.yml` is the non-secret generator input and
`MacCompanion.xcodeproj` is checked in for normal Xcode use. The project does
not contain a development team, certificate selector, provisioning profile,
managed entitlement, Keychain group, update key, or credential. Official
signing values are supplied only by the controlled local or release job.

## Bound target

- Product: `Mac Companion.app`
- Bundle identifier: `media.jenny.maccompanion`
- Version/build: `0.1.0` / `1`
- Deployment floor: macOS 26.0
- Form: persistent `LSUIElement` menu-bar application
- Dependencies: local `CompanionMacApp` and `CompanionMacUI` products plus the
  copy-time-signed permanent Agent command-line tool
- Runtime: hardened
- App Sandbox: disabled, matching the Stage 0 direct-distribution baseline
- Entitlements: none; Persistent Content Capture is deliberately absent
- Privacy resource: exact copy of the indexed Mac containing-app
  `PrivacyInfo.xcprivacy`

## Provisional build evidence

With `DEVELOPER_DIR` selecting the installed Xcode 27 beta:

1. A code-signing-disabled Debug build completed from the checked-in project.
2. An automatic Apple Development Debug build completed with the locally
   supplied development-team setting.
3. A manual Developer ID Application Release build completed with the locally
   supplied team and identity settings.
4. Independent `codesign --verify --deep --strict` inspection accepted the
   Release app and its designated requirement.
5. The Release executable is a universal arm64/x86_64 Mach-O, has the hardened
   runtime flag, carries the expected Jenny Media team and Developer ID chain,
   and has no entitlements.
6. Built `Info.plist` inspection returned the expected bundle identifier,
   version, build, and menu-application role.
7. Byte comparison proved the built privacy manifest is identical to the
   normative candidate resource.
8. Direct launch remained alive in the application run loop until the smoke
   test terminated it.
9. The complete `scripts/validate.sh` gate passed after the target and ledger
   changes, including repository-material, dependency, privacy, signing,
   packaging, release-evidence, Swift test, cross-platform build, and
   disposable-probe checks.

Normal Keychain inspection outside the restricted automation sandbox also
reports both the Apple Development and Developer ID Application identities as
valid. The earlier zero-identity observation was therefore a sandbox visibility
artifact, not evidence that replacement certificates were needed.

Gatekeeper correctly classifies this local Release build as an unnotarized
Developer ID app. No notarization, stapling, DMG construction, or publication
was attempted; those would be false release evidence at this stage.

## Remaining gates

- Repeat the target build and platform evidence with stable macOS 26 and Xcode
  26.6 before any release-candidate claim.
- Use the now-bound embedded Agent identity to prove local
  designated-requirement/audit-token authentication, lifecycle registration,
  update choreography, and clean uninstall. Packaging alone does not satisfy
  those gates.
- Add final icon, onboarding, Sparkle, packaging, notarization, stapling, and
  Gatekeeper evidence only against the exact external-alpha candidate.
- Add Persistent Content Capture only after Apple approval and a matching
  profile; its absence does not block Observe, Act, or ordinary app work.
