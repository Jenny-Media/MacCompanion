# iOS 1.1 screenshot handoff

The **34 reviewed final JPEGs** are under [screenshots/en-US/](screenshots/en-US/).
[artwork-manifest.json](artwork-manifest.json) records their relative paths,
dimensions, SHA-256 hashes, source provenance and raw-capture hashes.
[screenshot-copy.json](screenshot-copy.json) remains the caption and order authority.
Only selected sanitized exports belong in application Git. Raw captures, source
fixtures, rejected probes, bezels, build products and logs remain outside Git.

## October 29 Mac grid refresh

Nine final images are replaced:

- Large and medium iPhone: Desktop and Compose Text.
- iPad: Desktop and Compose Text.
- Duo: Tabletop, Book Compose Text and Book Desktop.

The five desktop scenes use the native Finder **Mac Apps** icon grid from the
previously approved store artwork. Only its remote-Mac pixels were extracted;
the old marketing frame and iOS controls are excluded. Compose scenes use a
native TextEdit window with synthetic text: “Hello from Mac Companion.” and
“Typed here. Sent to my Mac.” The grid appears behind the editor in the wide
scene. Neither Mac window controls nor app controls are repainted.

The other **25 final JPEGs remain byte-identical** to the prior manifest: 19
approved core compositions and the six 1.1 Backup & Restore / What Syncs images.
The manifest therefore records 19 reused exports and 15 new native shipping-view
captures. This does not relabel any Simulator app as TestFlight binary 167.

| Family | Output dimensions | Selected images |
| --- | --- | --- |
| Large iPhone | 1320 × 2868 | 9 |
| Medium iPhone | 1206 × 2622 | 7 |
| iPad | 2064 × 2752 | 9 |
| Duo | 2853 × 2007 Book; 2007 × 2853 Tabletop hero | 9 |

The light Focused artwork, captions and official bezels are retained. Every
native screen is included with proportional scaling and the device aperture's
corner mask. The iPad Compose composition uses the real landscape keyboard
layout plus an enlarged, uniformly scaled crop of its native Compose panel.
The full device screen also remains visible. Device controls, text and keyboard
pixels are not rewritten for the composition.

## Capture provenance and device retention

The private Simulator harness compiles the shipping viewer and composer from
candidate source `028c955040b2429c6e6ede8f48adfe7a642c0d15`. The repository's
Apps, Native, Packages and specification inputs were checked against that
candidate. The private bundle is `dev.maccompanion.storegrid.ios`; its entry point
and capture driver stay outside Git. It opens no Mac transport and is never
uploaded to Apple. The prepared Mac scenes establish appearance, not delivery
of text to a physical Mac.

Destinations ran sequentially with explicit UUIDs, per-device locks, the managed
compiler lease, parallel testing disabled and a single concurrent destination:

- Reused large iPhone: `FF42D9EA-2237-4CD5-9A65-0525BE1B196B`, iOS 27.0.
- Reused iPad: `2A3A688F-E93C-45BF-A0F2-B1807FF1C64F`, iPadOS 27.0.
- Reused Duo: `93322CC3-1471-4BF3-BDBF-632537D1C875`, iOS 27.1.
- Created reusable medium iPhone QA destination:
  `0D54DA09-3BEA-4A25-8043-CC9CA50111B8`, iOS 27.0. The required compatible
  project model was missing. This device is retained, is not disposable and was
  returned to Shutdown after capture. No medium image was fabricated by scaling
  a larger phone capture.

The three reused devices remain booted as initially found. Duo Book and Tabletop
use native Device Hub postures and inner display 3. Their real system divisions
were recorded: a 40-point vertical Book division and a 40-point horizontal
Tabletop division. No test division override was used. The original Closed
posture was restored after the capture test exited. Temporary 9:41 status-bar
overrides were cleared, capture locks released and all four devices retained.
No simulator was erased or deleted, and no other project's device was used.

## External evidence and application boundary

The refresh sources, raw captures, native test results, rendered export manifest,
before/after gallery and store application evidence are outside application Git:

`/Users/yihong/.codex/visualizations/2026/10/29/01a18624-5e6b-70c1-9d77-38f779abea0a/ios-1.1-mac-grid-refresh/`

Its `gallery/index.html` provides the before/after comparison, and
`gallery/refreshed-screenshots.jpg` provides the nine-image contact sheet.
The earlier backup/sync capture evidence remains in the adjacent
`ios-1.1-store-materials/` handoff.

At the October 29 artwork checkpoint, all nine replacement images had finished
processing and were assigned to the draft.
Reload verification confirmed all 34 screenshots in order: seven medium iPhone,
nine large iPhone, nine iPad and nine Duo images. The external
`evidence/asc-final-verification.json` records the saved filenames, unchanged
copy hashes, build 167, manual release and Prepare for Submission status.
The 25 unchanged files remain byte-identical. No asset Add for Review, app
Update Review or Submit action was used at that screenshot-refresh checkpoint.

On October 30, the owner authorized withdrawal and resubmission to correct the
separate Header and Search Results creatives. Four native-grid replacements
were applied across the main page and Remote Desktop custom page, and all four
placements were verified after reload. The existing 34 screenshots were checked
again and remain unchanged. The six-item package entered Waiting for Review
on October 30 under submission `609f17ea-1224-4399-84d5-4cdc62714fc8`, with build 167 and manual
release. The four final PNGs are now archived in [screenshots/en-US/creatives/](screenshots/en-US/creatives/)
and the manifest’s `creativeAssets` collection. The external `creative-assets/`
directory retains source provenance, placement mapping, before/after previews,
failed attempts and the historical resubmission receipt; those sources are not committed.

On November 4, iOS 1.1 (167) was verified Ready for Distribution and the six-item
review was complete with all items Approved. Earlier draft and Waiting for Review
observations above are historical checkpoints. The archive contains 34 store
screenshots plus four separate Header/Search creatives, not 38 store screenshots.

These captures establish displayed native UI only. They do not establish
physical Mac input, backup round-trip behavior, signed iCloud delivery, or
physical Duo acceptance. The [reviewer setup](reviewer-setup.md) retains those
separate acceptance checks. Build 167, manual release, current live copy,
custom product pages and the historical review conversation are preserved.
