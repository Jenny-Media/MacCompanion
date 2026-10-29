# iOS 1.1 screenshot handoff

The **34 reviewed final JPEGs** are versioned under [screenshots/en-US/](screenshots/en-US/).
[artwork-manifest.json](artwork-manifest.json) records their relative paths,
dimensions, SHA-256 hashes, source/reuse provenance and original raw-capture
hashes. The authoritative captions and order are [screenshot-copy.json](screenshot-copy.json).
Only these selected, sanitized exports are committed under the narrow release
artwork exception in `AGENTS.md`.

Raw captures, rejected attempts, capture fixtures, source bezels and logs remain
outside application Git at:

`/Users/yihong/.codex/visualizations/2026/10/29/01a18624-5e6b-70c1-9d77-38f779abea0a/ios-1.1-store-materials/`

The external handoff's `index.html` is the review gallery. Its original manifest
retains the detailed composition/capture evidence; the committed manifest is a
portable inventory of final exports, with no raw images, fixtures or logs.

Six new backup/sync exports were staged only in App Store Connect Asset Library
on October 29. At the last saved 20:07 UTC inspection, three were ready and three
were Processing. They were not assigned to the 1.0 version or submitted for
review. The owner chose to preserve 1.0; see [the store handoff](README.md#asset-library-staging-and-retained-10-record).

## Selected sequence

The seven approved 1.0 core compositions remain byte-identical for each display
family: Desktop, Terminal, Compose Text, Pro keyboard customization, Files,
Trackpad & Keyboard, and no-helper Mac setup. Duo keeps its approved Tabletop,
Book Terminal and Book Compose opening order. Their original capture/build
provenance is retained; they are not relabeled as fresh build-167 captures.

Fresh captures add **Backup & Restore** and **What Syncs** after the seven core
images for the large iPhone, iPad and Duo. The medium iPhone retains its approved
seven-image set. The compatible medium model is absent from the current QA
inventory; the large iPhone is used for the new phone screens without creating
another simulator or fabricating a medium-device capture.

| Family | Output dimensions | Selected images |
| --- | --- | --- |
| Large iPhone | 1320 × 2868 | 9 |
| Medium iPhone | 1206 × 2622 | 7 |
| iPad | 2064 × 2752 | 9 |
| Duo | 2853 × 2007 landscape; 2007 × 2853 Tabletop hero | 9 |

The new captions are “Your setup. / A backup away.” and “Your controls. / Across
devices.” Sync remains visibly optional; no screenshot claims that a real Apple
Account synchronized during capture. Credentials and trust exclusions remain in
the native scope screen. The setup composition continues to state that no Mac
Companion helper is needed.

## Capture and acceptance boundaries

New raw captures use the shipping Backup & Restore and Sync & Security views
from candidate source `028c955040b2429c6e6ede8f48adfe7a642c0d15`, hosted in a
private Simulator-only QA app. The app entry point injects an empty synthetic
library and a cloud transport that refuses writes/removal. It navigates to the
shipping What Syncs screen normally. No production view, label, control, profile,
credential or entitlement is modified. The private QA app is not TestFlight
binary 167 and is never uploaded.

Existing compatible Mac Companion phone, iPad and Duo QA simulators are reused
with their UUIDs passed explicitly and per-device locks held. Destinations run
sequentially with parallel testing disabled. Record their UUIDs, runtime, initial
and final state and native test results in the external manifest. Preserve prior
fixtures and all raw captures. No simulator creation, reset, erasure or deletion
is part of this work.

The three native UI journeys passed. XCTest's main-screen attachments on Duo
selected the inactive outer display and were black; those probes are retained
and excluded. The selected Duo images instead use native `simctl io screenshot
--display=3` captures, after visual confirmation in Device Hub. Its native Open
posture was used for the two new forms, then its original Closed posture was
restored. The iPhone and Duo remain booted as before; the iPad was returned to
its original Shutdown state. All three devices are retained and their locks
released. No other project's simulator was touched.

Each new final composition places its unchanged native capture proportionally
inside the existing approved official bezel and Focused visual style. The full
native screen remains visible. Caption artwork is separate from the app pixels;
no native text or controls are repainted. Inspect every new export and the
combined gallery before later application. Images are opaque RGB JPEGs at the
exact selected dimensions, with no EXIF or XMP metadata in the committed exports.

Synthetic screenshots establish displayed UI only. They do not establish backup
round-trip behavior, signed iCloud delivery, physical Mac input, or physical Duo
acceptance. Use [reviewer-setup.md](reviewer-setup.md) for those pending checks.
The external evidence records failures/rejected probes separately. Existing 1.0
assets, store selections and custom product pages remain untouched.
