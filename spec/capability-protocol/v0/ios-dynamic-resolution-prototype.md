# iOS dynamic resolution experiment

The tested resize handoff has moved into Native/VNC. The normal app uses the
landscape-only Advanced controls specified in [ios-desktop-size.md](ios-desktop-size.md).
This document retains the historical experiment and measurement contract.

This is an opt-in disposable experiment under `Experiments/DynamicResolutionPrototype`.
It is not linked into normal application targets. It preserves the current SSH
forwarding, host-key trust, ARD authentication and input ownership. It adds no
host helper and no authentication or encrypted record-layer implementation.

## Scope

Test whether the built-in Screen Sharing service accepts an explicitly requested
Apple virtual-display configuration on the existing classic ARD connection.
Successful writes are not acceptance: a matching new framebuffer, validated
single-display layout and a complete newly presented baseline are required.
If that is unsupported, the experiment reports that result; it must not quietly
negotiate a different authentication scheme or repeatedly retry a rejected request.

The candidate wire facts come from the pinned Open Screen Sharing source
`b73c815abb0cc59154ebe2a437aede698a0fa8b2`, particularly
`internal/rfb/messages.go` and `internal/rfb/virtualdisplay.go`. This is not an
Apple-published protocol contract or proof of support on the classic connection.
The packet builder is an independent bounded implementation of those field facts.

Display selection uses an eight-byte candidate message: type 13, selector 1
for all displays (ID zero) or 0 for a single display, two reserved zeros and
a big-endian 32-bit display ID. Selection requires an ID from the validated
current layout, and success requires fresh matching layout and pixels.

## Candidate configuration

All multibyte fields are big endian. Message 29 has a four-byte header containing
type 29, reserved zero and a 16-bit body length. The body starts with 16-bit version
1, 16-bit count 1 and a reserved 32-bit zero. Its one descriptor has a 156-byte
header and one 28-byte mode. The descriptor length is 184. Its bytes 2 through 121
are zero; offset 122 contains flags 1, offset 126 contains 4, offsets 130/134 are
IEEE-754 float physical width/height in millimetres (points / 132 * 25.4), and
offsets 138/142 contain the maximum pixel width/height. Offsets 146/148 are zero,
150 contains 7 and 154 contains mode count 1. The mode contains four 32-bit
dimensions (pixel width/height then point width/height), a 64-bit IEEE-754 refresh
rate and 32-bit flags zero. Refresh is 30 Hz in this experiment. Density is 2.

Reject non-finite, zero, negative or excessive sizes before integer conversion.
Preserve the viewer aspect ratio, growing small viewports to at least 600 points
on the short side and 800 on the long side before applying resource limits.
Round point dimensions down to multiples of four, within 600–1664 points per
axis, 3328 pixels per axis and 6 million total pixels. Reject aspect ratios that
cannot satisfy both the minimum usable desktop size and resource limits.
These conservative minima avoid sending phone-sized Mac desktop modes; they are
not a claim that every Mac accepts all sizes above them. Ignore keyboard height
changes; a user explicitly applies the current full viewer bounds. No request is
made while backgrounded, input-only, unauthenticated, reviewing text, or with
local pointer interaction active. The sole socket owner releases sent input,
retires old input/frame epochs and sends a single pending request. No queued
input may cross a display change.

During an explicitly requested display change, a validated single-display layout
may announce new backing dimensions without a standard DesktopSize rectangle.
For Fit Phone require the virtual-display flag and at most 6 million pixels; for
physical selection require the requested display ID. Admit those dimensions only
on the socket owner, within the normal framebuffer bounds, retiring the old
baseline and requiring new complete pixels. Do not infer a display from an image
or resize an unrelated session. Keep metadata usable for display selection after
its UI callback has consumed the pending layout notification.

A different host-selected size is not acceptance of the requested size. On the
six-second request deadline recover at the validated current host geometry and
record outcome 4 for a different virtual size, or outcome 3 if unconfirmed. Do
not reconnect or resend the resize automatically. Outcome 2 still requires the
exact requested backing dimensions, matching layout and complete new pixels.

## Benchmark journal

Periodic samples once per second and samples at numeric request/connection-state
transitions contain only a schema version, monotonic uptime, a local
session token, numeric geometry, booleans and an explicit allowlist of aggregate
frame/cursor/transport counters. Never record hostnames, accounts, passwords,
keys, clipboard, typed input, arbitrary diagnostic dictionaries or pixels.
Samples are gathered without blocking the main thread; one write can be in
flight. Sampling stops when the view is hidden or the app is inactive. A fresh
owner gets a fresh token so rates cannot span reconnects. Stop recording at 4 MiB; do not automatically delete or overwrite existing
benchmark evidence. Tests consume fixtures
indexed exclusively by `spec/fixtures/manifest.json`.

## Admission

Simulator tests verify packet bytes, bounds, stale-owner retirement and sampling
privacy. Synthetic socket tests can prove the client handles a resize, not that
Apple accepts the request. A physical built-in-server acceptance test is still
required before any production integration. High-performance video, Apple RSA/SRP
authentication and the encrypted record layer remain outside this experiment.
