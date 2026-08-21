# Permanent embedded Mac Agent target evidence

Date: 2026-08-21

Status: provisional packaging and signing proof on Xcode 27 beta; Agent remains
deliberately inert and this is not lifecycle or release-candidate evidence

## Scope

The checked-in Mac project now contains the permanent
`MacCompanionAgent` command-line-tool target and embeds its signed product in
`Mac Companion.app/Contents/MacOS/MacCompanionAgent`. The containing app also
copies the exact LaunchAgent property list to
`Contents/Library/LaunchAgents/media.jenny.maccompanion.agent.plist`.

The Agent entry point imports the two intended Agent platform products and then
waits in `dispatchMain()`. It does not construct a listener, open local IPC,
create keys, register itself, start capture or input, or report readiness. This
checkpoint proves product topology and code identity without silently granting
runtime authority.

## Primary-source basis

Apple's current
[`SMAppService.agent(plistName:)` documentation](https://developer.apple.com/documentation/servicemanagement/smappservice/agent%28plistname%3A%29)
requires the LaunchAgent plist under the containing app's
`Contents/Library/LaunchAgents` directory. Apple's
[helper migration guidance](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
uses `BundleProgram` as a path relative to the containing bundle. Apple's
[helper embedding guidance](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
uses a target dependency and a Copy Files phase with copy-time signing.

The Agent is therefore a separately signed, extensionless Mach-O helper, not a
nested app bundle. No new Developer portal App ID was created for this
checkpoint; the build path requires a unique code-signing identifier for the
standalone helper, while future entitlements or provisioning capabilities can
reopen the portal-registration decision.

## Bound target

- Xcode product type: command-line tool
- Embedded executable: `Contents/MacOS/MacCompanionAgent`
- Code-signing identifier: `media.jenny.maccompanion.agent`
- LaunchAgent label: `media.jenny.maccompanion.agent`
- LaunchAgent program: `Contents/MacOS/MacCompanionAgent`
- Runtime policy: `RunAtLoad` and `KeepAlive` after explicit registration
- Deployment floor: macOS 26.0
- Runtime hardening: enabled
- App Sandbox: disabled, matching the approved direct-distribution baseline
- Managed entitlements: none
- Installation product: skipped as an independent product; embedded in the
  containing app
- Privacy bundle owner: the containing app; the logical Agent manifest is
  required to be byte-identical to the outer app's manifest

The generator explicitly passes
`-i $(PRODUCT_BUNDLE_IDENTIFIER)` through `OTHER_CODE_SIGN_FLAGS`. This is
necessary because a non-bundled command-line tool otherwise defaults to its
filename as its code-signing identifier even when
`PRODUCT_BUNDLE_IDENTIFIER` is set.

## Provisional build evidence

With `DEVELOPER_DIR` selecting the installed Xcode 27 beta:

1. The unsigned Debug build produced the exact outer-app, LaunchAgent-plist,
   helper-executable, and privacy-resource layout.
2. An Apple Development Debug build completed with the team supplied only on
   the command line.
3. A clean Developer ID Application Release build completed with team and
   identity values supplied only on the command line.
4. Independent `codesign --verify --deep --strict` inspection accepted the
   outer app and embedded Agent.
5. The outer designated identifier is `media.jenny.maccompanion`; the embedded
   Agent designated identifier is exactly
   `media.jenny.maccompanion.agent`.
6. Both Release executables are universal arm64/x86_64 Mach-O files with
   hardened runtime and the expected Developer ID trust chain.
7. The built LaunchAgent plist contains only the exact four approved keys and
   its `BundleProgram` resolves to an executable file.
8. The outer privacy manifest is byte-identical to the normative Mac
   containing-app candidate, which is also byte-bound to the Agent template.
9. Gatekeeper rejects the local candidate only as
   `Unnotarized Developer ID`, as expected before notarization.

The first Developer ID inspection caught the helper's default
`MacCompanionAgent` identifier. The generator was corrected and the artifact
was rebuilt from clean state before any evidence claim. This demonstrates why
the final embedded copy, rather than target settings alone, is authoritative.

## Regression boundary

`scripts/validate_permanent_apple_targets.py` now fails if the generator or
checked-in project loses the tool target, copy-time signing, reverse-DNS
signing flag, LaunchAgent destination, exact plist contract, inert entry point,
or no-secret/no-profile boundary. It runs in the repository-wide validation
gate before compilation.

The privacy validator separately owns source-graph API inventory and enforces
the Agent-to-containing-app bundle-owner relationship and exact manifest byte
equality.

## Remaining gates

- Construct `SMAppService.agent(plistName:)` from the permanent app, then prove
  explicit register/unregister convergence and the physical login, logout,
  crash, update, and uninstall matrix.
- Bind the package-owned service graph only after authenticated local IPC and
  durable startup are installed; until then the menu app must continue to show
  the Agent as unavailable.
- Prove audit-token/designated-requirement peer authentication using these
  final code identifiers.
- Repeat exact signing and lifecycle evidence on stable macOS 26/Xcode 26.6.
- Notarize, staple, package, and run Gatekeeper only against the exact external
  beta candidate.
- Add the managed Persistent Content Capture entitlement only after Apple
  approval and a matching profile. Its absence does not block this Agent,
  Observe, Act, or ordinary nonpersistent Control work.
