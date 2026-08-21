# Permanent SMAppService identity composition evidence

Date: 2026-08-21

Status: provisional signed construction and negative side-effect proof on Xcode
27 beta; not registration, readiness, authenticated IPC, or release evidence

## Claim

The permanent Mac containing app now constructs and retains the exact two
`SMAppService` identities required by the frozen lifecycle design:

- Agent role: `SMAppService.agent(plistName:
  "media.jenny.maccompanion.agent.plist")`
- menu login role: `SMAppService.mainApp`

Each raw framework service is wrapped by
`SMAppServiceRawLoginRoleV1`, then
`AgentLoginRoleConvergingServiceV1`, and finally the shared
`AgentLoginRoleEffectExecutorV1`. The app retains that executor but does not
call it during launch.

This binds the permanent target to the already tested registration,
postcondition, rollback, and Agent-before-menu ordering without moving those
rules into app UI. Registration remains distinct from process start and from
authenticated Agent readiness.

## Explicit no-authority boundary

Constructing the service identities is side-effect free. Neither the containing
app source nor the composition source may call `register`, `unregister`, or
`setEnabled`. The dashboard continues to show the Agent as unavailable, and
no lifecycle action is wired to this retained executor yet.

Only a later application composition may invoke the executor after either:

1. an explicit user enable command has durably recorded the intended state; or
2. restart reconciliation has loaded a previously durable enabled intent.

That later slice must still bind authenticated local IPC, Agent-owned lifecycle
state, process-start postconditions, approval recovery, and truthful dashboard
publication. Merely observing `SMAppService.Status.enabled` cannot claim that
the Agent is ready.

## Verification

With the installed Xcode 27 beta:

1. The regenerated project includes the app's direct
   `CompanionAgent` and `CompanionAgentPlatform` products and compiles the
   exact composition source.
2. A code-signing-disabled arm64 Debug build completed.
3. Launching that containing app left
   `gui/<uid>/media.jenny.maccompanion.agent` absent from launchd and started
   no `MacCompanionAgent` process. The app remained alive until the smoke test
   terminated it.
4. A clean Developer ID Release build completed.
5. Independent strict deep code-sign verification accepted the containing app
   and embedded Agent with exact distinct identifiers
   `media.jenny.maccompanion` and
   `media.jenny.maccompanion.agent`.
6. Both executables remained universal arm64/x86_64 hardened-runtime Mach-O
   files; the LaunchAgent plist and outer privacy resource remained exact.
7. The permanent-target validator rejects a missing or substituted plist name,
   service role, adapter/convergence/executor layer, app retention, package
   dependency, or any implicit lifecycle mutation in the permanent sources.
8. The privacy policy now follows all four direct containing-app Swift product
   roots while preserving the Agent's separate executable roots and
   containing-app bundle ownership.

## Remaining gates

- Wire the explicit dashboard enable/disable path to a durable lifecycle product
  rooted in authenticated Agent authority.
- Prove `requiresApproval`, not-found, idempotent convergence, compensation,
  and disable cleanup against the real services.
- Add authenticated local IPC before any Agent fact can reach the dashboard.
- Run the physical login, logout, lock, crash, update, disable, and uninstall
  matrix on clean users.
- Repeat signed evidence with stable macOS 26/Xcode 26.6 and the controlled
  release environment.
