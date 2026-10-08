# Normal native development apps installed on Mac and iPhone

The normal Mac Debug app was rebuilt with a newly pinned catalog for the exact
source-built Sunshine package used by the passing App and Window Simulator
journeys. The production-supervisor package has the same 119 host file hashes
as that tested package and adds its required source/compiler construction record.
The normal staging gate verified the production supervisor, complete catalog,
strict containing-app signature, and unchanged bundled host files. The compiled
selector executed against the installed signed app and returned the native
backend factory. Release selection remains closed to this development catalog.

The previous Mac app was copied and byte-inventoried before replacement. The
current signed app was installed at `~/Applications/Mac Companion.app`, launched,
and its existing registered Agent was restarted without deleting pairing or
grants. The Agent's loaded executable path resolves to the new installed bundle.
The separate installed Sunshine app and processes were left alone. The previous
Mac bundle is retained under `/private/tmp` for rollback.

The normal iOS app was rebuilt with the current native Moonlight engine for
`iphoneos`, signed by Xcode with an existing Apple Development profile that
includes the paired iPhone 18 Pro Max, and installed as
`media.jenny.maccompanion.ios`. The device inventory confirms the installation.
The development builder was corrected to keep XcodeGen's numeric build-version
setting as text; the final installed bundle reports version `0.1.0` and build `1`.
The first launch attempt was refused by iOS because the device was locked;
there is no device launch, pairing, playback, or physical input acceptance yet.

## Evidence

- Stable `bash scripts/validate.sh` passed after the catalog change, with 115
  indexed fixtures. Private log:
  `/private/tmp/maccompanion-final-installed-native-validation-20260928.log`,
  SHA-256 `8356dfa8258f7afb10ed1612a18ee5c0de5a760a70db4fc9ad1dfe6ca533eeac`.
- Installed Mac app and staged candidate have the same 193-file SHA-256 inventory
  digest `333b3af0d8c25d1631b850bc63d6ba31a34fe08388d847a8dd24b3d8a004bbeb`.
  The installed containing signature passes strict deep verification with the
  existing app identity requirement.
- Installed Mac catalog SHA-256:
  `94b4ad520f2811ba13f4b7c06a0f22dbf68ca4fc92d040183d7de47360545ccd`.
  Source-built production package manifest SHA-256:
  `add6ff10e5e6535c402f5b9f0335b4aeec2baee8b1b33adfe73f37d1a9a049fc`.
- Mac app build, stage, and production selector records:
  `/private/tmp/maccompanion-current-native-mac-build-signed-20260928.log`,
  `/private/tmp/maccompanion-current-native-mac-stage-20260928.json`, and
  `/private/tmp/maccompanion-installed-native-catalog-probe-20260928.log`.
- Signed iPhone executable SHA-256:
  `acccad709c62a2396c76ced8a1d0185e2f2d32dc24394b2bc8f3b27f2b8bfdd1`.
  Xcode's signed device build and profile/device inclusion passed; the physical
  device install returned success and later app inventory listed this bundle.

This is a development installation and source/catalog selection result. The
installed Mac GUI's continuous capture/TCC attribution, physical LAN pairing,
Moonlight playback and actual macOS system input still require a fresh unlocked
device journey. Viewport bitrate, corresponding-source assembly, and release
admission remain separate work. No profile, certificate, device identifier,
secret, screenshot, or typed content is tracked here.
