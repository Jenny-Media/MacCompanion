# Agent Keychain provisioning repair

Date: 2026-08-23

Status: signed construction and installation passed on Xcode 27 beta; fresh
visible `SMAppService` enable/readiness acceptance remains open

## Failure diagnosis

The first visible **Enable Mac Companion** attempt registered the per-user
Agent, but the Agent exited before readiness. Unified logging established the
exact boundary:

- `taskgated-helper` rejected `media.jenny.maccompanion.agent` because it
  found no eligible provisioning profile;
- the Agent then reached `SecKeyCreateRandomKey` for its permanent P-256
  Secure Enclave host identity;
- adding that token-backed key to the data-protection Keychain failed with
  `NSOSStatusErrorDomain -34018`, `errSecMissingEntitlement`;
- the foreground setup owner timed out and correctly unregistered its owned
  Agent registration without granting Observe, Act, or Control.

The original extensionless command-line helper could carry a code signature
but had nowhere to embed the provisioning profile authorizing its application
identifier and default Keychain access group. This failure is independent of
the still-pending Persistent Content Capture managed entitlement.

## Repair

Following Apple's *Signing a daemon with a restricted entitlement* guidance,
the permanent Agent target is now a minimal app-like daemon wrapper:

- bundle: `Contents/Helpers/MacCompanionAgent.app`;
- executable:
  `Contents/Helpers/MacCompanionAgent.app/Contents/MacOS/MacCompanionAgent`;
- bundle and signing identifier: `media.jenny.maccompanion.agent`;
- private Keychain group:
  `$(AppIdentifierPrefix)media.jenny.maccompanion.agent`;
- app sandbox: disabled; hardened runtime retained;
- no AppKit lifecycle, window, Dock item, or new remote capability;
- the existing `SMAppService.agent(plistName:)` LaunchAgent remains owned by
  the containing app and its `BundleProgram` now points to the wrapped
  executable.

The containing app copies and signs the complete nested Agent bundle under a
standard code location. Release packaging now requires both the nested Agent
executable and its `Contents/embedded.provisionprofile` instead of accepting
an unprofiled standalone executable.

## Signed construction evidence

With Jenny Media signing authority supplied only to the local Xcode
invocation, Xcode registered this Mac as a development device and produced an
eligible wildcard team development profile. The signed nested Agent claims
exactly:

- `com.apple.application-identifier =`
  `<private-team-prefix>.media.jenny.maccompanion.agent`;
- `com.apple.developer.team-identifier` equals the privately confirmed Jenny
  Media Team ID;
- `keychain-access-groups =`
  `[<private-team-prefix>.media.jenny.maccompanion.agent]`.

The complete containing app and nested Agent both pass strict code-signature
verification and designated-requirement checks. Xcode's embedded-binary
validator accepts the helper placement and signing relationship. The
development profile expires in August 2027. No profile, certificate, Team ID,
device identifier, or other private signing material is tracked in the
repository.

The exact signed app was installed at
`~/Applications/Mac Companion.app`; the previous installed bundle was retained
recoverably under `/private/tmp`. The repaired app was launched, but no
command-line Agent bypass was used and no privacy permission or remote grant
was accepted.

## Post-profile process-lifetime repair

The first visible enable attempt after the provisioning repair proved that
`SMAppService` registered the new nested executable, launchd spawned it, and
the earlier `taskgated-helper` and `errSecMissingEntitlement` failures were
absent. It then exposed a separate process-entry defect: the async Agent main
called `dispatchMain()` while already executing on the main dispatch queue.
libdispatch intentionally trapped with
`BUG IN CLIENT OF LIBDISPATCH: dispatch_main called from a block on the main
queue`, and launchd repeated the crash until the foreground setup owner timed
out and unregistered its role.

The Agent entry point now directly awaits the retained running owner's restart
request and then awaits its terminal cleanup. It creates no unstructured task
and calls no nested dispatch main loop. Source validation rejects reintroducing
`Dispatch`, `dispatchMain()`, `withExtendedLifetime`, or an unstructured
`Task` at this process boundary. The complete repository validation gate passes
after this correction.

## Remaining acceptance

1. The user performs another fresh visible **Enable Mac Companion** action
   using the build containing both repairs.
2. Logs show no `taskgated-helper` rejection and no `-34018` Keychain error.
3. The Agent completes the consent-bound disabled-to-enabled transition,
   restarts, and reports reciprocal authenticated readiness.
4. Only after readiness should pairing or any separately granted Observe, Act,
   or Control scenario begin.
5. External distribution still requires an explicit
   `media.jenny.maccompanion.agent` App ID and matching Developer ID profile,
   followed by stable-Xcode, notarization, packaging, and Gatekeeper evidence.

## Primary sources

- [Signing a daemon with a restricted entitlement](https://developer.apple.com/documentation/xcode/signing-a-daemon-with-a-restricted-entitlement)
- [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)
