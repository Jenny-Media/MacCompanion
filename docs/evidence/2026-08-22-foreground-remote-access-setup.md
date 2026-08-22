# Foreground remote-access setup composition

Date: 2026-08-22

## Claim

The permanent containing app now owns the explicit foreground transition from
an unregistered or interrupted disabled Agent to a durably enabled Agent and a
fresh authenticated dashboard attempt. The transition does not use the normal
two-role enable executor: it registers only the Agent before consent, admits
only the one-use disabled bootstrap exchange, and registers the visible menu
role only after the exact durable receipt.

## Construction

- `AgentLoginRoleConvergingServiceV1.acquireForBootstrap()` reads the exact
  pre-mutation registration status inside the same actor that performs and
  verifies registration. It distinguishes a role created by this setup attempt
  from a preexisting role without caller inference.
- `MacLocalXPCRemoteAccessBootstrapClientV1` authenticates only the exact
  same-team Agent identity, copies every borrowed reply before returning from C,
  and exposes only hello, offer read, enable, cancellation, and bounded
  invalidation. It cannot read status or use pairing, presentation, diagnostics,
  Observe, Act, Control, or network authority.
- `MacRemoteAccessSetupCoordinatorV1` enforces Agent registration, exact offer,
  explicit confirmation, exact command, durable receipt, then menu registration.
  It automatically compensates only a registration it introduced before the
  enable-send boundary. Preexisting or post-send ambiguity retains the Agent and
  becomes `outcomeUnknown`; exact disabled-offer decline is the sole safe
  preexisting-registration removal in this setup owner.
- The main-actor setup facade preserves callback FIFO order through one bounded
  event relay and publishes typed state through one ordered UI relay. Buffer
  overflow, malformed order, cancellation, and invalid receipts fail closed.
- `MacCompanionProductApplicationV1` treats `SMAppService` status only as a
  routing input. Absent registration exposes setup, enabled registration attempts
  a new authenticated dashboard, approval-required status exposes recovery, and
  only an exact setup receipt starts the post-setup dashboard attempt.
- The permanent menu UI displays the fixed no-relay, per-user Agent, independent
  permission, and Mac-authority facts before confirmation. It provides distinct
  decline, retry, login-item recovery, menu-convergence, and outcome-unknown
  states without claiming readiness from registration or receipt.

## Deterministic verification

Focused tests cover inert construction, exact effect order, explicit decline,
pre-authentication invalidation, post-send ambiguity, invalid receipt, menu-role
retry, owned versus preexisting registration, cleanup failure, ordered facade
delivery, registration-based launch routing, dashboard fallback, and the exact
receipt-to-dashboard transition.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
CompanionMacApplicationPlatformTests
```

Result: all 26 focused tests passed on Xcode 27 beta. The 15 focused login-role
convergence tests and 83 local-XPC tests also pass. A code-signing-disabled
Debug build of the permanent `MacCompanion` scheme succeeds and embeds the
Agent and LaunchAgent property list. The complete public validation entry point
also passes, including all 1,389 `MacCompanionKit` Swift tests and all eight
platform-probe tests.

## Non-claims and next gate

This checkpoint does not claim that `SMAppService` registration, launchd,
consent UI, durable receipt, Agent restart, dashboard authentication, readiness,
or status executed across the two signed processes. It does not open pairing,
presentation, networking, Observe, Act, or Control.

The next gate is a signed clean-state acceptance run: begin with both login
roles absent and durable intent disabled, confirm the fixed setup UI, observe
Agent-only registration, exact durable receipt and Agent restart, verify
visible-menu convergence, then require a fresh same-team readiness
acknowledgement and typed status snapshot before the dashboard reports
availability.
