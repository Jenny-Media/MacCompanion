# Host focus-event capability authority

Date: 2026-08-23

## Outcome

The Agent now owns a bounded capability authority for privacy-filtered focus
events. For each accepted Interactive session it issues an independent exact
event sequence and binds a newly generated target token to the event message
ID, sequence, current acknowledged surface and coordinate fence, exact focus
token/revision/projection, and local monotonic expiry.

Only the latest event target is current. A newer event revokes its predecessor,
every Focused Region target is one-use, target identifiers cannot be reused
within the session, and the authority has an explicit 100,000-event memory and
sequence bound. Desktop recommendations carry no target capability and revoke
any prior Focused Region target.

## Surface transition binding

The Agent surface-control handler creates this authority only for the exact
initial Desktop session. A Focused Region selection must consume its current
token before the menu-process resolver is called. The resolver's returned
descriptor must then reproduce the exact bound focus projection and still pass
the existing runtime transition authority. Any token, expiry, session, epoch,
surface, coordinate, or focus mismatch closes the surface-control handler.

If the current surface is already a Focused Region, the Agent refuses another
focus event unless input has first been reported paused and the verified focus
has actually changed or disappeared. The event authority itself does not claim
that input was released; the later concrete observation pipeline must obtain
that proof from the menu runtime before asking the Agent to publish the event.

## Verification

- Four pure authority tests prove canonical event creation, latest-only and
  one-use consumption, non-reuse, expiry, fence rejection, and paused recovery
  from an existing Focused Region.
- Five Agent surface-handler tests pass, including an initial Desktop through
  event issuance and exact Focused Region descriptor binding.
- The repository-wide gate passes 73 fixtures, all 1,482 discovered Swift
  tests, macOS/iOS cross-builds, unsigned permanent application builds, and
  eight platform authority probes.

This checkpoint does not yet observe Accessibility focus, issue the
menu-to-Agent sanitized candidate over authenticated XPC, send an event on the
network primary stream, construct a live ScreenCaptureKit crop, or apply Smart
Zoom automatically on iOS. Those remain the next host/product checkpoints.
