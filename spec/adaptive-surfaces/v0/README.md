# Adaptive surfaces shared authority profile v0.1

Status: normative for bundle-independent surface and input fencing; network message encoding and capture adapters remain unfrozen.

Adaptive surfaces let a client view the desktop, one application, one window, or a focus-derived region without turning Accessibility metadata into a second remote-control authority.

## Authority tuple

Every descriptor and admitted input is bound to:

```text
(interactiveSessionID, authorizationEpoch, surfaceID,
 surfaceRevision, coordinateSpaceRevision,
 optional focusToken, optional focusRevision)
```

An input is admitted only while the matching descriptor is active and its half-open monotonic lifetime contains the current time. A stale session, epoch, surface, coordinate space, focus binding, future descriptor, or descriptor at its exact expiry boundary is denied.

Surface and coordinate revisions advance together by exactly one for each selection or fallback. The host pauses and releases input before applying a new capture source. After the executor commits, the host publishes a discontinuity, the new descriptor, and a clean keyframe. Input resumes only after the client acknowledges that exact descriptor fence.

Fallback during a transition advances from the newest issued target, never from the older visible surface. Suspension or ending invalidates every token and cannot resume the authority in place.

## Privacy and bounds

- Encoded output is at most 1920 by 1200 and 2,304,000 pixels.
- Metadata uses a closed allowlist. Titles, text values, document contents, URLs, and Accessibility object identities are forbidden.
- Desktop descriptors expose no application, window, focus, parent, or fallback token.
- Application and window descriptors use opaque tokens; window titles are not metadata.
- Focus-derived descriptors bind an opaque focus token and revision. Secure focus is classified `secureOpaque`; it does not expose or enable text content.
- Interaction classes and metadata fields are sorted, unique closed enums.

The indexed fixtures under `spec/fixtures` are the authoritative examples for this shared model. They are not yet wire envelopes. Exact remote messages must be added fixture-first to the capability protocol before socket code uses these structures.
