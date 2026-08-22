# Agent bootstrap production binding

Date: 2026-08-22

## Claim

The permanent Mac Companion Agent now binds the exact disabled-Agent XPC
exchange to the durable bootstrap authority and exits cleanly for launchd
restart only after the enabled receipt has been sent, or when a committed
enable can no longer be acknowledged. This path grants no readiness, network,
pairing, presentation, Observe, Act, or Control authority.

## Closed profile and handler

- Canonical disabled/stopped preparation selects the internal
  `disabledRemoteAccessBootstrap` server profile and injects the one retained
  durable intent-store instance from preparation.
- Durable recovery selects the separate closed `authenticationOnly` profile,
  which cannot receive a bootstrap handler. Mismatched handler/profile
  construction fails before listener creation and reveals no wire-visible mode.
- The exact authenticated peer may perform only one five-second offer read
  followed by one five-second enable command embedding that exact offer.
  Request ownership, operation IDs, listener generation, peer generation,
  timeout, cancellation, and replacement are fenced together.
- Borrowed enable bytes are copied synchronously before the C callback returns,
  then decoded with the existing canonical 4,096-byte codec. Handler failure,
  malformed output, timeout, substitution, duplicate work, or reply failure
  cancels the current peer without an application-error envelope.

## Durable acknowledgement and restart

The Agent returns an enable acknowledgement only after the authority has read
back the exact successor intent. A successful send emits one terminal
`remoteAccessEnabled` event. The permanent process owner latches that event,
finishes the selected local service and prepared root, and exits successfully;
launchd `KeepAlive` then starts a fresh Agent that reloads enabled intent and
must independently earn readiness/status.

If durable enablement completed but peer replacement, cancellation, timeout,
or reply construction/send prevents acknowledgement, the authority emits the
same one-shot restart requirement. It never replies to a replacement peer and
does not continue serving the disabled profile against enabled durable state.
The restart latch is durable for the process lifetime even when signalled
before the executable begins waiting.

## Verification

Focused Xcode 27 beta verification passes:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit \
  --filter 'Companion(LocalXPCPlatform|AgentPlatform)Tests'

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit \
  --filter CompanionAgentApplicationPlatformTests
```

Results: all 82 local-XPC platform tests, 102 Agent-platform tests, and 10
Agent-application-platform tests passed. New cases cover exact profile/authority
matching, durable-commit reply loss, one-shot acknowledgement-failure restart,
disabled-versus-recovery runtime selection, and an early latched restart.

The complete repository validator also passes with 64 indexed fixtures, 947
repository files, 1,205 historical blob paths, 308 production Swift source
files, 1,370 package tests, every supported cross-build, and all 8 platform
probe tests.

## Non-claims and next gate

This checkpoint does not yet register the Agent from an explicit foreground
menu action, implement the menu bootstrap client or consent UI, converge the
visible-menu login role, or prove the exchange between the two signed app
processes. It starts no network listener and does not claim enabled Agent
readiness. The next checkpoint is the resumable foreground `SMAppService`
registration and menu-client transaction, followed by signed disabled-to-ready
acceptance evidence.
