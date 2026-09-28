# Sealed managed native host

Date: 2026-09-27. This checkpoint restricts the experimental managed Sunshine
host and preserves the normal Mac bootstrap's configured native runtime.
It does not complete normal-app streaming or installation.

## Implemented

The normative managed host profile and its manifest-indexed admission fixture
preceded implementation. The manifest now indexes 102 JSON fixtures. Existing
pairing, session-signature and approval semantics are unchanged.

The pinned Sunshine patch disables its configuration server and plaintext HTTP
listener when the local process owner selects managed enrollment. Authenticated
HTTPS retains serverinfo, applist, launch and cancel; native pair, resume and
appasset routes are absent and return a bounded HTTP 404 response. The backend
selects this profile explicitly. The process owner clears any inherited profile
flag before selecting managed or upstream reference behavior. The host remains
loopback-only, with sole Desktop, native input/audio/UPnP disabled and original
Control deadline/retirement ownership preserved.

Normal Mac bootstrap now preserves the injected native runtime when replacing
its interactive authorities. Previously the reconstructed platform services
silently dropped that optional runtime.

The disposable host-probe build defines a diagnostic-only TLS compilation flag
that permits the three forbidden route requests and requires HTTP 404. Normal
SDK builds retain only the four allowed operations and require HTTP 200. The
probe never exports its native client private key.

## Verification

Selected stable toolchain: Xcode 27.0 at
`/Applications/Xcode.app/Contents/Developer`.

- Pinned upstream source/submodule/artifact/patch verification passed.
- The source-built managed Sunshine host accepted the attested in-memory client
  for HTTPS serverinfo and sole-Desktop inventory. Pair, resume and appasset
  returned HTTP 404 with the admitted certificate. Plaintext HTTP and Web UI
  connection attempts were refused while approved HTTPS remained available.
- Unregistered client rejection, busy-port rejection, malformed certificate,
  invalid proof, Control revocation and joined private-state cleanup passed.
- All eight native TLS cases passed, including wrong pin, unregistered identity,
  cancellation, oversized/mismatched bodies, expired host and wrong purpose.
- Fifteen Simulator tests passed: four native engine lifecycle, eight UIKit
  owner/lifecycle and three identity/XML/encrypted-route admission checks.
- Simulator and iPhone components built unsigned. All six framework records and
  both real probes match the same frozen source-input hash. The real host probe
  also matches the rebuilt host binary hash.
- Full `bash scripts/validate.sh` exited 0 on the stable toolchain. This includes
  normal Mac product compilation, including the preserved runtime injection.
  `git diff --check` passed.

Source-input SHA-256:
`de92f2c6569a5ec374a0df0a72ba78edd713cfa0a039639110a4aea507b983de`.
Managed Sunshine binary SHA-256:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.

Reports and diagnostics remain outside Git under
`/private/tmp/maccompanion-sunshine-moonlight-20260926`.
Repository validation log: `/private/tmp/maccompanion-sealed-validation.log`.
The actual host probe uses synthetic Control authority and does not launch or
present video. The Simulator checks verify components; normal-app native
streaming, input and physical behavior are not established by this checkpoint.

## Remaining

Implement the concrete authenticated Mac runtime provider and approved display
mapping, admit dependency/process/TCC packaging, configure the normal client
adapter, and prove primary enrollment → native launch → decoded frame → Stop.
Native presentation/input admission, signed installation and physical acceptance
remain open. No new normal app was installed for this checkpoint.
