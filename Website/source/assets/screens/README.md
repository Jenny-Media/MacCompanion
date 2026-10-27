# Website screenshot exports

These nine WebP images are sanitized public marketing assets explicitly requested
for the website redesign. The originals remain in the external **iOS 1.0 screenshot
preview v10** set documented in
[`docs/app-store/ios/1.0/screenshots.md`](../../../../docs/app-store/ios/1.0/screenshots.md).
Raw captures, sample input files, fixture adapters, signing material, and local
review evidence are not part of the website or this repository change.

The native UI is captured from the app's Simulator QA host. The source set checks
all 642 application inputs against revision `35a060ed`; subsequent changes through
the website base `370b9194` affect release documentation only. Retained captures
keep their original device/build provenance as detailed in the source handoff.
The locale is en-US. These are interface and layout examples, with no claim of
physical iPhone Duo acceptance or uploaded-build acceptance.

- Desktop content is a composition of genuine Finder and TextEdit windows with
  synthetic documents on a bundled macOS wallpaper. It is not a live desktop stream.
- Terminal uses a Simulator-loopback SSH fixture and synthetic output. Displayed
  commands are sample content.
- Files displays a seeded sample directory; no completed transfer is depicted.
- Device frames come from the matching prepared Apple bezel assets in that set.
  Tabletop uses the existing frame rotated into portrait; no physical bend or
  unsupported hardware geometry is invented.

Each full native screen is clipped to its matching rounded frame aperture, then
the combined image is proportionally resized and WebP-compressed at quality 87
with Pillow's method 6. No interface control is painted, removed, or retouched.
The manifest records original capture and frame hashes, output hashes, dimensions,
and sizes. The nine exports total less than 500 KiB. The main page links to a
plain-language sample-content disclosure beside the hero screenshots.

To reproduce the exports with Pillow installed, run:

```sh
python3 Website/export_screens.py --source-set /path/to/mac-companion-store-design-v10
python3 Website/build.py
python3 Website/check.py
```

The exporter verifies every selected original capture and frame hash before
writing. Its manifest and this note are source-only and are not served publicly.

Original aperture coordinates, in full bezel pixels:

| Frame | Frame size | Screen x, y | Screen size |
| --- | --- | --- | --- |
| iPhone 18 Pro Max | 1470 × 3000 | 75, 66 | 1320 × 2868 |
| iPhone Duo Book | 3093 × 2247 | 120, 120 | 2853 × 2007 |
| iPhone Duo Tabletop | 2247 × 3093 | 120, 120 | 2007 × 2853 |
| iPad landscape | 3000 × 2300 | 124, 118 | 2752 × 2064 |
