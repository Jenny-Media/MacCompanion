# Portable package of the archive-rebuilt host

Date: 2026-09-27. Development packaging and acceptance checkpoint.

`scripts/package_rebuilt_source_host.py` creates a distinct development package
from explicitly pinned Sunshine/runtime rebuild reports. It verifies all static
and dynamic host link inputs and the complete source-built runtime prefixes,
then copies the host, rebuilt certificate CLI, six runtime dylibs and a freshly
compiled production supervisor into one bundle. The supervisor uses the explicit
stable SDK, C11 warnings as errors and macOS 26 deployment target.

Every non-system library reference becomes loader-relative, every library search
path is removed, and each native binary plus the bundle receives a development
signature. Complete file maps, construction origins, supervisor source/compiler
records, deployment commands, signatures and closed dependency resolution are
checked. Notices for the host, runtime dependencies, linked codecs, Boost and JSON
are retained. Corresponding-source completeness remains false.

The new profile has its own verifier. The older package builders/verifiers remain
unchanged, preserving their exact construction bindings. The disposable runners
explicitly select the new verifier and use the rebuilt OpenSSL static libraries
through a verified provenance binding. This selection changes no remote pairing,
approval, signature or grant behavior and admits no new permanent target resource.
The normal Mac root's existing compiled catalog still selects its previous exact
package; this new candidate is only explicitly selected in the test runner.

## Construction and relocation evidence

- Source host rebuild report SHA256:
  `9689321ebc4caac7f39b857300f1087ad1849cd322630e8f5e9b01da64d895c0`.
- Source executable SHA256:
  `f435f23e3e1da70a524a4861211c59bf707600df7c50a76db6eee160f1efcf8b`.
- Runtime rebuild report SHA256:
  `ad949c6d1b2d4809a3469f811580710694cc76b23f9de971fa0748ee9747c9c9`.
- Final package: `/private/tmp/maccompanion-source-rebuilt-portable-host-20260927-v2`.
- Package manifest SHA256:
  `1ee79a835e04c12b3c6a4a3a64e5b07d99455f3122a65ec28f96e2435bc55492`.
- Packaged host executable SHA256:
  `44bac4190f8d3f9562dd1ecae0f8d9c541cc3291fe15173d94b1325df93f1aa4`.
- Packager SHA256:
  `b7ba04f09b2eb2e2082f5a72a370a4dc68944fe89088348048c2667c11fe193c`.
- All ten native binaries and the bundle pass strict signatures, closed dependency
  and complete file-map checks. The initial package was superseded before live
  testing to include the complete linked-library notices and supervisor flag check;
  both construction outputs are retained.
- A copy at a fresh location starts the host help command and bundled OpenSSL
  without development library search overrides. Self-signed credential generation
  and verification pass in private temporary state, which is removed afterward.
  Changing a byte in the copied certificate CLI is rejected; the original remains
  valid. The historical production-supervisor package also still verifies.
- Normalized relocation result:
  `/private/tmp/maccompanion-source-rebuilt-portable-host-relocation-20260927.json`,
  SHA256 `171835569a5d1f74f8d8188e32e013736c4d7b710ddedae4e3f60aff043b7dae`.

Required stable Xcode repository validation passed with 109 indexed fixtures:
`/private/tmp/maccompanion-source-rebuilt-package-handoff-validation.log`.

## Fresh live Simulator acceptance

The exact final package passed the dedicated iPhone 17 / iOS 27.0 Simulator lane,
ID `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`. One XCTest completed four visible native
sessions in 237.509 seconds, with zero failures and cleanup verified. Typing,
keyboard dismissal, modifiers, shortcuts, pointer, background revocation,
reachability-loss teardown, fresh restart, Stop and fresh Observe passed. Actual
capture geometry stayed physical 5120 by 2134, logical 2560 by 1067 and encoded
1920 by 800. Final input effects remain synthetic.

Report: `/private/tmp/maccompanion-agent-xpc-evidence.84vrr4dh/signed-simulator-report.json`.
Report SHA256: `1745741d9e31d38b77343afa23f26f4ea4b74b3c0996cd461fec41db458211e1`.
Combined source/runner SHA256:
`e343b7d8ee6f62a171ee6d06ead596f733b2891f72da5bd69229f4a56c674721`.
Current client/shared native-input SHA256:
`ad8ef45eb4af2325468f87a7b300e1f97e380767929af0ae1c7c1220bb34c1dc`.

This proves fresh startup, authenticated enrollment and actual native playback
through the signed isolated composition with this rebuilt package. It uses test
custody/consent and the shared normal UIKit owners in the harness. It does not
pair or stream through the installed normal iOS application or prove installed
Mac GUI/TCC ownership. No physical device was accessed.

## Scope and remaining work

The rebuilt packet covers the host and dependencies; the tested client engine is
still the separately built current candidate, not yet reconstructed from the
historical source packet. Full client reconstruction and current source snapshot
assembly remain open. The package does not prove bit-identical reproduction,
release admission or normal installed-app acceptance. No installed Mac app,
separate Sunshine service, physical phone, privacy setting or login service was
modified by construction/relocation tests.

Normal paired Control, signed normal GUI/TCC acceptance, LAN and real final system
input remain open. Native App/Window capture and visible-area bitrate remain open.
Simulator live input effects use a synthetic final sink; test key custody/consent
remain separate from normal app storage/hardware-key requirements.
