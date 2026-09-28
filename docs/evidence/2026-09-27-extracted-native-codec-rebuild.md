# Native host codecs rebuilt from the source packet

Date: 2026-09-27. Development source-rebuild evidence; no release admission.

`scripts/rebuild_native_source_codecs.py` rebuilt all seven host codec libraries
from the retained source packet in a fresh isolated output directory. It requires
an explicit manifest SHA256, verifies archive and extracted file maps, checks the
four codec revisions and source completeness, and binds the retained codec build
record to its archived first-party builder. The recorded stable Apple toolchain
and SDK must match. No original candidate or installed app was replaced.

## Archive-specific adaptations

The upstream codec build assumes Git repositories and fetches version tags for
SVT-AV1 and x265. The packet contains source files and revision records, without
Git databases. The new lane makes a separate working copy, removes tag fetches
from that copy, and supplies x265's archive version metadata from the pinned
commit and retained build record's 4.1 release tag. The original archive's
`x265Version.txt` refers to an older 4.0 revision; it is not used as authority for
the pinned checkout. Before/after hashes of both adapted files are reported.
No Git history is invented and the retained source payload stays unchanged.

The recorded codec configuration is remapped to the new source/output locations.
Generated sources still receive the upstream codec patches. Package lookup is
restricted to the fresh prefix and the Apple SDK is explicit for compilation,
linking and assembly. This does not claim an operating-system network-denial
sandbox or bit-identical reproduction. The two upstream tag-fetch operations
are absent from the build, and the lane supplies all codec source from the packet.

## Evidence

- Source packet: `/private/tmp/maccompanion-native-source-inputs-20260927-v2`.
- Manifest SHA256:
  `146be6eecba35e73aa7ff5d585cabfb4343fa6d2442fea6ae74a012424ee8216`.
- Archive SHA256:
  `d62017a4a67553e0dd01d87dcd722ebee5ef3d987319246bc595cf54406a2d10`.
- Build output: `/private/tmp/maccompanion-source-codec-rebuild-20260927-v1`.
- Report: `rebuild-report.json`, SHA256
  `578871c693b970b2b1d0152dbd25dda74df0a7bab91906da84ec7ae36d45d66c`.
- Builder SHA256:
  `3cc01df44f511e955c105fb71e880ae291460eb088246361f276315329777aa0`.
- Configure, compile, install and final readback passed. The prefix contains 183
  files, including `libavcodec`, `libavutil`, `libswscale`, `libcbs`, `SvtAv1Enc`,
  `x264` and `x265` static libraries. Inspected deployment commands in all seven
  archives report macOS 26.0. Retained source-payload readback remained exact.
- An incorrect manifest pin was rejected before output creation.
- Required stable Xcode repository validation exited zero with 109 indexed
  fixtures: `/private/tmp/maccompanion-source-codec-rebuild-handoff-validation.log`.

## Remaining scope

The normal Mac app and separate Sunshine application were running during this
work and were left intact. The rebuilt codecs are separate artifacts and have
not been linked into or tested with a fresh streaming host. Full Sunshine and
client engine/adapter reconstruction from the delivered source packet, assembled
corresponding-source delivery and exact source-to-product acceptance remain open.
The packet is historical and does not include the latest promoted iOS source
snapshot. Source completion and permanent release admission remain false.

Normal paired Control, signed Mac GUI/TCC acceptance, physical installation and
real final system input remain open. The Simulator's protected-storage limitation
does not justify relaxing the normal app's storage or hardware-key requirements.
Native App/Window capture and visible-area bitrate remain independent pending work.
