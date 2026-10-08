# Managed native transport encryption prerequisite

Date: 2026-09-27

## Change

The normal Mac managed enrollment backend now sets both `lan_encryption_mode`
and `wan_encryption_mode` to `2` (mandatory). The normative managed-host profile
and its existing manifest-indexed admission fixture were updated first. Existing
enrollment signing and certificate admission remain backed by their existing
golden vectors. No upstream cipher, key construction or pairing algorithm changed.

The current client already sends `corever=1`, accepts only an exact `rtspenc`
launch URL, and requests all native stream encryption flags. The additional host
requirement prevents an authenticated client from launching a plaintext session.

## Verification

The isolated live managed-host probe passes with the production backend:

- Requests with `corever` omitted or `0` return status 403 and `gamesession=0`.
- A valid encrypted launch returns the exact approved encrypted stream route.
- A plaintext OPTIONS request on the pending encrypted RTSP session receives only
  an encrypted error, followed by socket closure; timeouts and plaintext replies
  fail the check.
- Exact admitted TLS client acceptance, other-certificate rejection, sealed routes,
  port conflict, invalid proof, original deadline and revocation cleanup still pass.

The probe substitutes runtime platform effects and does not decode video or claim
an authenticated primary/XPC journey. Its historical host binary is recorded
separately from the rebuilt portable host used for the Simulator acceptance lane.

Report: `/private/tmp/maccompanion-sunshine-moonlight-20260926/managed-host-probe-report.json`

Report SHA-256: `ab07cd32fd3e4a384940ce3276598b9bc0410b6db7b40a4d7de4d594576acf3a`

Combined source input SHA-256: `244bd7373a9a7533f181d36b2b109b41cfd6649c6ee5c1e799880e703445ca4a`

Host binary SHA-256: `c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d`

## Current rebuilt-host Simulator acceptance

The dedicated iPhone Simulator (`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`)
passes all four visible native sessions with the archive-rebuilt portable host.
The production wrapper uses mandatory encryption in this run. Decoded presentation,
correlated input admission, pointer, keyboard, modifiers, shortcut delivery,
background/route recovery, Stop, fresh Observe and cleanup pass. Final input uses
a synthetic host sink. One UI test passed, zero failed; elapsed time 243.678 seconds.

Report: `/private/tmp/maccompanion-agent-xpc-evidence.5bc_qexd/signed-simulator-report.json`

Report SHA-256: `aede379b0bae54e2bfc6247f4f5178977cec579efd0b8c8e2759ea196f81bd72`

Combined source SHA-256: `1142607dbcd01ebda35a5208bd6dfc70444fe708a949dc8d832e454739033d4f`

Native source input SHA-256: `244bd7373a9a7533f181d36b2b109b41cfd6649c6ee5c1e799880e703445ca4a`

Portable host manifest SHA-256: `1ee79a835e04c12b3c6a4a3a64e5b07d99455f3122a65ec28f96e2435bc55492`

Stable Xcode 27.0 `bash scripts/validate.sh` passed, including all 109 indexed
fixtures, package tests and required platform builds. Local validation log:
`/private/tmp/maccompanion-mandatory-encryption-validation.log`.

## Remaining product work

At this encryption checkpoint the backend still bound loopback. Subsequent
[IPv4 listener work](2026-09-27-managed-native-ipv4-listener.md) implements the
trusted listener scope and records live non-loopback host verification. Full
normal paired network acceptance remains separate. Normal paired GUI/TCC,
physical phone installation/acceptance, real input, App/Window native capture,
visible-area bitrate and current corresponding-source assembly remain open.
