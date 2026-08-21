# Apple privacy manifest profile v0

Status: normative for current source and candidate target resources.

Apple requires privacy manifests to record data collection on all platforms and
required-reason API use for iOS, iPadOS, tvOS, visionOS, and watchOS. The
current direct-distribution macOS product is outside the required-reason
platform list, but its covered API use remains inventoried for re-review.

## Data practice

Mac Companion has no developer relay, analytics, advertising, tracking domain,
or third-party SDK. Status, audit, pairing, and Interactive Control data moves
only in real time between devices operated by the same person, or remains on
those devices; Jenny Media LLC and third parties cannot access it. Under
Apple's definition, this is not developer collection. Every candidate manifest
therefore declares tracking false, no tracking domains, and no collected data.

This is a claim about the current product architecture, not permission to add a
server or telemetry. Any developer-accessible transmission, retention beyond a
real-time request, analytics SDK, crash uploader, or tracking domain requires a
policy and manifest revision before code is admitted.

## Required-reason API result

The iOS client release graph currently calls none of Apple's five covered API
families. Its manifest includes an empty `NSPrivacyAccessedAPITypes` array.

Current covered APIs exist only in the macOS release graph:

- `ProcessInfo.systemUptime` in Host status and Agent monotonic timing;
- `.systemSize` and `.systemFreeSize` in Host disk status; and
- conservative `stat`/`fstat` inventory in the durable deny latch and macOS
  remote-access intent store.

The Host and Persistence files are whole-file `#if os(macOS)` guarded. The
Agent timing and Agent-platform intent files are not guarded, but both targets
are outside the iOS app's transitive Swift target closure. Validation checks
both conditions from the current package graph instead of assuming that a
shared module name implies an API is compiled for iOS.

macOS candidate manifests omit `NSPrivacyAccessedAPITypes` because Apple does
not currently require reason declarations on macOS. They do not claim those
APIs are absent. The machine-readable inventory preserves their exact source
locations and counts.

`DispatchTime.now().uptimeNanoseconds` is not on Apple's current covered list
and is not treated as `systemUptime` or `mach_absolute_time` by this profile.

## Target boundary

The templates cover the iOS app, macOS containing app, and embedded macOS Agent
service. They are not permanent Xcode targets. When final targets are created,
the release build must prove each executable bundle receives its exact template
at Apple's required bundle location. If final menu/login topology creates
another executable bundle, it must receive a separately indexed manifest before
promotion.

Apple's categories and approved reason catalog can change. Re-check the primary
documentation immediately before any App Store submission and whenever the
source inventory or target graph changes.
