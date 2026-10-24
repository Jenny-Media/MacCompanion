# Native input queue and gesture ownership

Keep the single socket worker and existing RFB packets. Separate three lifetimes:
queued user work, local gesture cancellation, and global lifecycle retirement.

- All user input producers use one queue-capacity policy. Internal cleanup
  barriers preserve ordering but do not consume the 512-user-event allowance.
  Coalesce adjacent barriers after removal, bounding total entries by twice the
  user allowance plus one. Derive occupancy from entries instead of maintaining
  a second counter that can drift during coalescing, cancellation or draining.
- Each admitted native gesture owns a cancellation token shared by its queued,
  copied and actually-sent events. Local cancellation retires only the active
  gesture. Completed gestures and prefixes sealed by a shortcut barrier remain
  valid, including when a newer gesture is canceled or hits queue pressure.
  The worker also releases canceled sent gestures through its read-service hook
  when no new input is queued, without waiting for the current frame to finish.
- Background, pause, stop, display/layout replacement and interruption retain
  the global lifecycle epoch. They retire all old gestures, including copied
  events, and release actually-sent state on the socket worker. A local token
  must never bypass those gates or revive a retired lifecycle.

Regressions cover all producers at the capacity boundary, true overflow,
repeated cancellation and barrier bounds, completed versus active gestures,
queued/copied scroll and pinch prefixes followed by canceled/failed fresh
gestures, and existing pause/interruption/replacement/stop behavior. Verify exact
golden RFB packet order through the production socket worker, using a controlled
held write rather than claiming actual network-backpressure reproduction.

Use Xcode.app and managed build/QA workspaces. Run focused native regressions,
the related lifecycle/shortcut suites, and scripts/validate.sh. Keep test evidence
outside Git. No wire/authentication, signing identity or persistence changes.

## Viewer gesture admission

Expose ordinary-input availability from the session's existing reservation and
readiness gates, sampled under its queue lock. Share a viewer admission predicate
across pointer movement, clicks, holds, scrolling, pinch, cursor-follow and touch
feedback. Check before changing local cursor targets, origins or gesture state;
rejecting a packet at the transport alone leaves a latent target for the next tap.
Keep lifecycle cleanup and previously accepted queued/copied input independent.
Do not gate incoming host cursor observations or introduce a second reservation
flag in the viewer. Cancel/completion opens admission immediately unless another
connection or presentation gate remains closed.

Regressions cover pointer, trackpad and tabletop surfaces with both Cancel and
completion, the first subsequent click and fresh gesture, independent lifecycle
gates, stale owner callbacks, host cursor reception, and retained prefix ordering.

## Verification

The three targeted native regressions failed against the unchanged previous
production source, then passed after the structural change. All 105 selected
native cases passed across gestures, lifecycle, shortcut sequences and remote
controls, including global-retirement compaction and the viewer admission cases.
They include eight user-input producers at capacity, eight queued/copied and
scroll/pinch combinations, failed
recognizers, true overflow and 1,000 cancellation cycles. Golden packet checks
run through the production socket worker with a held write.

The wrong-click regression also failed against d483162 before the viewer gate,
then passed for all eight pointer/trackpad/input-only/tabletop and
Cancel/completion cases.
While reserved, gesture callbacks cannot change local targets or touch feedback,
and the first subsequent click uses the unchanged target. Independent lifecycle
and stale-owner gates remain closed; incoming host cursor observations continue.

The normal Simulator app matches all 634 production source fingerprints.
scripts/validate.sh passed with stable Xcode.app 27.1 (27A9275). Earlier full UI
journeys and physical build 157 predate this follow-up; this change is verified
by the native Simulator regressions rather than a new physical-device install.
