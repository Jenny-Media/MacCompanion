# Native system-appearance feasibility — 2026-08-21

## Decision

Do not implement or advertise `setAppearance(system | light | dark)` as an
initial native Mac Companion action. There is no documented AppKit API for
changing the user's system-wide appearance, and the documented scripting
surface cannot represent all three requested states.

Apple's [`NSAppearance`](https://developer.apple.com/documentation/appkit/nsappearance)
documentation scopes appearance selection to how AppKit renders an
application. Apple's
[`NSApplication.appearance`](https://developer.apple.com/documentation/appkit/nsapplication/appearance)
and [specific-appearance guidance](https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app)
likewise cover the application's own windows and views. They do not provide a
system-wide setter.

The installed macOS System Events scripting dictionary exposes a writable
Boolean `dark mode` property on `appearance preferences`. That supports an
Apple Event distinction between light and dark, but it has no value for the
user's automatic/system schedule. Collapsing `system` into `light` would make
the desired-state contract false.

## Why Automation is a separate capability

Controlling System Events is not a permission-free native provider. Apple says
[`NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
is required for APIs that send Apple Events. The
[`com.apple.security.automation.apple-events`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
entitlement allows an executable to prompt for cross-application Automation,
and
[`AEDeterminePermissionToAutomateTarget`](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)
models that target-specific decision.

That authority must not move into the network-facing Agent or the current
`CompanionNativeProviders` target. If later demand justifies a light/dark-only
Automation capability, it requires a separately reviewed, user-facing
menu-app adapter, explicit local onboarding, exact System Events targeting,
read-back verification, revocation handling, and signed clean-machine tests.
It would be a new capability contract, not a hidden implementation of the
rejected three-state action.

## Rejected mechanisms

Mac Companion will not write undocumented global preference keys, restart the
Dock, or post undocumented appearance-change notifications. Those techniques
do not provide a supported, stable, permission-honest product contract.

## Re-entry conditions

Reconsider system appearance only if either Apple publishes a system-wide API
that represents automatic, light, and dark, or a later product stage approves
an explicitly Automation-backed light/dark capability after permission UX,
distribution, lock-state, revocation, and read-back evidence. Until then,
`setAudioMuted` remains the required MVP action and bounded keep-awake remains
the next candidate.
