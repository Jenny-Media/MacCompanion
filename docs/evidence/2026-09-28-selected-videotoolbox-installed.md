# Selected-surface VideoToolbox development installation

The normal Mac Debug app was rebuilt with the exact 119-file source-built host
package tested in the passing App and Window Simulator journeys. The catalog
digest was pinned in both the compiled normal Mac selector and the staging
gate. The signed app was staged, its complete inventory and containing-app
signature were verified, and its files were copied to the existing normal
installation at `~/Applications/Mac Companion.app`. The previous installed
bundle is retained at
`/private/tmp/maccompanion-installed-pre-videotoolbox-20260928.app`.
The new installed bundle matches the staged 197-file inventory. The existing
Agent service was restarted without changing registration, pairing or grants;
both Agent and menu app executables were observed loading from the new bundle.
The compiled Debug selector accepted the installed app's bundled native host
catalog.

The normal iOS app and its embedded Moonlight engine were rebuilt from the
final source input for `iphoneos`. Xcode signed the app with the existing Apple
Development profile, whose device list includes the paired iPhone 18 Pro Max.
The physical device accepted the install over the existing app, and a fresh
device inventory lists `media.jenny.maccompanion.ios` version 0.1.0 build 1.
The phone requires its passcode, so a launch or playback check did not run.
The update did not erase app data.

## Evidence

- Mac catalog SHA-256:
  `e6a46019ecbd18104400ef5a1891f05691029c1cb547bbcb44def70c7a67bb8f`.
- Exact staged/installed Mac app inventory digest:
  `e1c25fb5397f5b62162fc441bc92f5ae9315a47f11ed196b3dcf6e84df352a4c`.
- Installed Mac executable SHA-256:
  `c7fe2feeaa553030e4b56744fcb4f5502b3135dc87e914e6a3a6cc528eefc8f3`.
- Installed iPhone candidate executable SHA-256:
  `998e886b5f4ae7776e8db20bf822bb72817bb4f57831c02b35c627422cffafb3`.
- Private stage and physical install records:
  `/private/tmp/maccompanion-selected-encoder-probe-mac-stage-20260928.json`
  and `/private/tmp/maccompanion-selected-encoder-probe-iphone-install-20260928.json`.
- Final full repository validation passed with 115 indexed fixtures. Private
  log: `/private/tmp/maccompanion-selected-encoder-probe-handoff-validation-20260928.log`.
- Installed Debug catalog selector probe:
  `/private/tmp/maccompanion-selected-encoder-probe-installed-catalog-probe-20260928.log`.

The Mac containing signature passed strict verification. Xcode's iPhone
signing build succeeded and the device installed the app; local `codesign`
trust evaluation returned `CSSMERR_TP_NOT_TRUSTED` for both this and the
preceding device build, so it is not used as a passing local trust claim.
Installed Mac GUI capture/TCC continuity, paired LAN, physical playback and
actual system input remain unverified until an unlocked-phone journey.
