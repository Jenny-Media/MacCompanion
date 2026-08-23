# Update Agent startup-repair binding

Date: 2026-08-23

Status: permanent-target construction, focused tests, and an unsigned macOS
app build pass on Xcode 27 beta. No app, Agent, ServiceManagement role, local-
XPC session, Application Support store, or updater was started in this session.

## Outcome

`MacUpdateAgentReactivationPlatformV0` is the concrete boundary between the
bundle-independent recovery saga and platform effects. It maps every raw
ServiceManagement state into the closed recovery model, forwards exact
compare-and-swap persistence, and uses the existing converging registration
and completion-awaited unregistration owner. Its only public running-build
input is `MacUpdateAgentBuildReadinessV0`; the arbitrary closure seam is
package-only for tests, so a production caller cannot inject a build claim.

The readiness owner invokes the startup-only reciprocal signed-peer local-XPC
probe. It retries only ordinary launch-race start failure, invalidation, or
timeout, using at most four attempts and fixed 250-millisecond spacing. A
protocol-order violation, invalid policy, unknown error, exhaustion, or task
cancellation is terminal. Every individual probe cancels its client session.

`MacCompanionUpdateAgentReactivationCompositionV0` now constructs the running
containing-app build, system atomic receipt store, concrete platform binding,
and single-use startup reactivator. The permanent application retains this
composition and runs repair before it reads Agent registration for routing or
constructs the dashboard. The reactivator reads the receipt first: no receipt
means no registration or XPC effect. If composition or retained-receipt repair
is uncertain, routing becomes unavailable and no dashboard starts.

Construction prepares the private Application Support directory when the app
is actually launched, but opens no XPC session and changes no login role by
itself. This session compiled the app without launching it, so no live store
was created or inspected.

## Verification

Seven focused adapter tests cover closed registration mapping, persistence and
converged-effect forwarding, bounded launch-race retry, terminal protocol and
unknown failures, cancellation preservation, exhaustion, and invalid policy.
Forty-nine application-platform tests include proof that startup repair
finishes before registration-based route reconciliation and that repair
failure performs no registration read or dashboard construction.

The regenerated permanent Xcode project includes the composition source. This
unsigned command passes on Xcode 27 beta:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project MacCompanion.xcodeproj -scheme MacCompanion \
  -configuration Debug -destination platform=macOS \
  CODE_SIGNING_ALLOWED=NO build
```

The complete repository gate passes 73 authoritative fixtures, 35 update-
policy fixtures, 3 privacy manifests, 12 privacy fixtures, 16 required-reason
source records, 1,149 repository files and 1,957 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, release-evidence, and
permanent-target validator, 1,575 MacCompanionKit tests, 8 platform-probe
tests, and every supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

No retained receipt was exercised against the real Application Support store.
No live Agent was registered, unregistered, launched, or authenticated, and no
TCC prompt or updater action ran. The dashboard does not yet retain its
authenticated Agent build for runtime update shutdown, and the Sparkle user
driver still answers `.skip`; therefore this checkpoint enables neither a full
update check nor installation. Signed two-version recovery evidence remains
open.
