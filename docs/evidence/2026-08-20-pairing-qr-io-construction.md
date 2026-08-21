# Pairing QR input and output construction

Date: 2026-08-20

## Claim

The package now contains bundle-independent construction for the two missing QR
edges of pairing: a Mac Core Image renderer and a foreground iOS VisionKit
scanner surface. The scanner accepts only QR symbology, emits at most one
bounded ASCII `maccompanion://pair/v0.1/` candidate, stops before publishing it,
and never decodes, displays, persists, or logs the one-time secret. The existing
`PairingClientPresentation` remains the sole UI-facing authority that rejects
malformed, noncanonical, or expired payloads before a route is accepted.

The Mac renderer accepts only bounded ASCII product-prefixed text, uses Core
Image's QR generator at integral scale, selects level-L error correction so the
protocol's bounded byte-mode maximum remains representable, exposes no copy or
share action, and gives the image only a secret-free accessibility label.

## Platform basis

Apple documents that `DataScannerViewController` can scan QR codes, must be
checked with both `isSupported` and `isAvailable`, requires a camera usage
description, and needs user camera consent. Apple also documents that the QR
payload is available from the recognized barcode and that Core Image's QR
generator accepts message data plus L/M/Q/H correction levels. The implementation
uses only QR recognition, checks authorization after the user opens the scanner,
handles unsupported, denied, restricted, unavailable, and start-failure states,
and stops on cancel, disappearance, failure, or first admitted result.

## Verification

Four package tests prove that the content-free scan filter admits only bounded
ASCII product candidates and that the Mac renderer creates one square native
image representation while rejecting wrong-prefix, non-ASCII, and invalid-scale
inputs. The complete `CompanionClientUI` target cross-compiles for the iOS 17
Simulator triple with the VisionKit/AVFoundation controller, and the Mac UI
target compiles through the repository gate.

The SwiftUI surface is intentionally stateless. UIKit owns camera authorization,
visibility, cancellation, scanner child lifetime, and the one-shot completion
fence, preventing view recomputation from restarting a sensitive platform
resource.

## Boundary

No camera was opened by this evidence. The Simulator and command-line build do
not prove physical-device support, prompt wording, camera denial recovery,
background transitions, recognition quality, or that a maximum-size canonical
payload scans reliably from a real Mac display. Final iOS target construction
must add `NSCameraUsageDescription`, wire the existing **Scan Pairing Code**
action to this surface, and run the clean-device matrix. The Mac image remains a
lazy Core Image-backed `NSImage`; this sandbox cannot rasterize Core Image, so a
signed-app visual/scan round trip remains mandatory.
