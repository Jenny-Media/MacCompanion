# Sunshine rebuilt from the retained source packet

Date: 2026-09-27. Development source-rebuild evidence; no release admission.

`scripts/rebuild_native_source_host.py` rebuilt Sunshine using the pinned source
packet, separately pinned runtime/codec rebuild reports and retained Web UI npm
inputs. The script verifies the original archive/file map, exact host revision,
archived builder, all rebuilt dependency files and the recorded Apple toolchain.
It uses a new working copy; the retained source payload remains unchanged.

Boost and nlohmann JSON are extracted from the packet's verified source archives
and supplied through explicit FetchContent source directories with disconnected
mode enabled. The Web UI imports all 193 verified npm archives into a fresh cache;
installation uses offline mode, ignores install scripts, and has blank npm user
and global configurations. Provider/search overrides are cleared. No operating
system network-denial claim is made for every subprocess.

The archive has no Git database. Sunshine's existing CI metadata interface is
supplied an explicit development version `0.0.0`, branch `source-archive` and the
pinned Sunshine commit. This supplies truthful archive build metadata without
inventing Git history or claiming a release version. No upstream source patch was
added by this lane. The packet retains its previously admitted host changes.

## Evidence

- Source packet: `/private/tmp/maccompanion-native-source-inputs-20260927-v2`.
  Manifest SHA256:
  `146be6eecba35e73aa7ff5d585cabfb4343fa6d2442fea6ae74a012424ee8216`.
- Runtime rebuild report SHA256:
  `ad949c6d1b2d4809a3469f811580710694cc76b23f9de971fa0748ee9747c9c9`.
- Codec rebuild report SHA256:
  `578871c693b970b2b1d0152dbd25dda74df0a7bab91906da84ec7ae36d45d66c`.
- Web input report SHA256:
  `e6d8ca8b16b9be2775232260ceacfb662b9f4a50f2c51299b3108b92add6e00c`.
- Fresh output: `/private/tmp/maccompanion-source-host-rebuild-20260927-v1`.
  Report: `rebuild-report.json`, SHA256
  `9689321ebc4caac7f39b857300f1087ad1849cd322630e8f5e9b01da64d895c0`.
- Rebuilt host executable SHA256:
  `f435f23e3e1da70a524a4861211c59bf707600df7c50a76db6eee160f1efcf8b`.
- Builder SHA256:
  `dc6124164433f59ec73f73bc73c021154a3b21f10abc310939631d82077b97a8`.
- Configure, compilation and final readback passed. The final executable binds
  25 static link inputs and seven runtime libraries from the rebuilt prefixes.
  The offline web build produced 82 assets including index and PIN pages.
  Source packet, runtime prefixes, codec prefix and npm archives remained exact.
- Stable Xcode repository validation exited zero with 109 indexed fixtures:
  `/private/tmp/maccompanion-source-host-rebuild-handoff-validation.log`.

## Executable loading and remaining packaging

The initial unbundled version command failed in the dynamic loader because
`@rpath/libminiupnpc.21.dylib` had no resolvable development path. The unmodified
executable then passed `--version` using only the four verified runtime library
directories in an explicit development search path. The probe used its own mode
0700 state directory and started no listener or capture. Normalized result:
`/private/tmp/maccompanion-source-host-rebuild-20260927-v1/runtime-version-smoke.json`.
This proves loading in that development environment; the default unbundled loader
and portable packaging are not claimed to pass. The source artifact is unchanged.

The new host must be packaged with its rebuilt runtime libraries, certificate CLI
and supervisor, verified after relocation, and tested for startup and visible
video before replacing any previously tested candidate. Existing portable-package
acceptance applies to its historical artifact, not this executable.

Full client engine/adapter reconstruction, current source snapshot assembly and
corresponding-source completion remain open. The historical source packet does
not include the latest iOS promotion or these new rebuild scripts. No installed
Mac app, separate Sunshine app or physical phone was modified. Normal paired
Control, signed normal Mac GUI/TCC continuity, LAN/real system input, App/Window
capture and visible-area bitrate remain open; permanent release admission is false.
