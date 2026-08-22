# Public macOS session-state boundary

Date: 2026-08-22

## Question

Can the Agent use public macOS APIs to distinguish all protocol host states,
especially an unlocked current console from a locked screen and fast user
switching?

## Primary-source findings

- [`NSWorkspace`](https://developer.apple.com/documentation/appkit/nsworkspace)
  publishes workspace lifecycle notifications. Apple describes
  [`sessionDidResignActiveNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification)
  as a notification that the user session switched out, with the corresponding
  become-active notification describing a switch in. This is not a documented
  lock/unlock signal.
- [`CGSessionCopyCurrentDictionary`](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary%28%29)
  exposes public window-server session facts. The public
  [`kCGSessionOnConsoleKey`](https://developer.apple.com/documentation/coregraphics/kcgsessiononconsolekey)
  indicates whether the session is on the console, but the public dictionary
  contract does not include a screen-lock fact.
- [`SCDynamicStoreCopyConsoleUser`](https://developer.apple.com/documentation/systemconfiguration/scdynamicstorecopyconsoleuser%28_%3A_%3A_%3A%29)
  identifies the current console user. It does not document a lock-state
  distinction and therefore would not close the gap.

## Decision

The public facts are insufficient to publish `userSessionActive` or
`userSessionLocked`. Even a login-complete, on-console session owned by the
Agent's UID remains ambiguous. In accordance with the normative architecture,
the Stage 0 product maps that ambiguity to `otherConsoleUserActive`.

The product may publish `hostPreparingForSleep` from the public workspace
will-sleep notification and `serviceStoppingForLogout` for public power-off or
explicit finish. A session dictionary that says login is not complete remains
ambiguous rather than being misrepresented as logout. Wake and session-change
notifications resample facts but do not elevate the session to unlocked.

## Consequence

This conservative source can safely provide live clocks, unique response IDs,
pairing timing, and an Observe-visible coarse host state. It intentionally
keeps Interactive Control and operations that require an active or specifically
locked session unavailable. A later source may add those states only after a
supported public mechanism and lock-versus-fast-user-switching evidence are
proved on the release OS range.

Private or undocumented lock-state APIs are a no-go for the direct-distribution
MVP. Routing, Tailscale reachability, and user consent do not change this local
authorization fact.
