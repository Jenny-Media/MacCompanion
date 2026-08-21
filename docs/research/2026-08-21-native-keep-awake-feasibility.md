# Native keep-awake feasibility — 2026-08-21

## Decision

Proceed with a candidate-only, bounded native provider using Apple's public
IOPM assertion API. Do not advertise it in the first MVP registry until signed
physical behavior and a dedicated time-selection UI pass.

Apple documents that
[`IOPMAssertionCreateWithName`](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname)
requires no special privilege and returns an error when power management cannot
activate the assertion. The more specific
[`IOPMAssertionCreateWithDescription`](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti)
accepts a timeout, while
[`kIOPMAssertionTimeoutKey`](https://developer.apple.com/documentation/iokit/kiopmassertiontimeoutkey)
defines that timeout as an outer bound so a hung application cannot hold the
assertion indefinitely.

The selected
[`kIOPMAssertionTypePreventUserIdleSystemSleep`](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
prevents automatic idle sleep while allowing the display to dim. Apple states
that lid close, explicit sleep, low battery, and other reasons may still sleep
the system. This is a better product boundary than a display-sleep assertion:
the remote action does not light or force the display awake.

Apple requires every created assertion to be paired with
[`IOPMAssertionRelease`](https://developer.apple.com/documentation/iokit/1557090-iopmassertionrelease).
Mac Companion therefore owns one assertion, releases it on explicit stop or
replacement, and also sets the system timeout. Raw assertion IDs and IOKit
errors remain local.

## Remaining evidence

The documentation establishes API shape, not real product reliability. Signed
physical tests must still prove timeout accuracy, assertion attribution,
replacement and release behavior, Agent crash/logout cleanup, portable lid
behavior, and low-battery/thermal limitations. Until then the action remains
outside the advertised registry and outside the market-MVP promise.
