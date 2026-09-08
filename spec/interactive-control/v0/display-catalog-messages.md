# Interactive display catalog and selection v0.1

Status: normative closed schemas for choosing one online Mac display during an
active Interactive Control session. Catalog metadata is presentation only and
does not grant capture or input authority.

## Catalog exchange

`interactive.display.catalog.request` is an original authenticated primary
command request. Its body contains exactly `authorizationEpoch`, a positive
integer that must match the active session.

`interactive.display.catalog.response` correlates to that request. Its body
contains exactly:

- `authorizationEpoch` and the positive safe-integer `admissionRevision`;
- `selectedDisplayID`, an opaque UUID contained in `displays`;
- `validForMilliseconds`, from 1 through 10,000; and
- `displays`, a unique array of 1 through 16 candidates.

Each display candidate contains exactly:

- `displayID`, an opaque UUID that never contains a platform display ID;
- `ordinal`, a unique integer from 1 through 255;
- positive `pixelWidth` and `pixelHeight` values bounded by 65,535;
- signed 32-bit `layoutX` and `layoutY` origins;
- positive `layoutWidth` and `layoutHeight` values bounded by 65,535; and
- `isMain`, with at most one main display per catalog.

The four layout values are sampled from the online display's Core Graphics
global logical bounds. They share one coordinate space and exist only so the
client can normalize the relative arrangement into a local display picker.
They are not capture geometry, do not change the current surface descriptor,
and must never be used as remote pointer coordinates. Pixel dimensions remain
separate because backing resolution can differ from logical layout size.

The catalog exposes no display name, serial number, model, physical display
identifier, wallpaper, screenshot, thumbnail, or content. A client renders
generic names from the ordinal and main-display flag. It refreshes the catalog
after a topology change and fails closed if the selected opaque display is no
longer present.

## Selection exchange

`interactive.display.select` is an original authenticated primary command
request containing exactly `authorizationEpoch`,
`expectedAdmissionRevision`, and `displayID`. The host admits it only for the
active session owner, the exact current epoch and admission revision, and a
currently online candidate from a fresh catalog. Success follows the ordinary
Desktop surface-replacement exchange and does not resume input until the new
descriptor, discontinuity, clean frame, and acknowledgement are complete.

Unknown, missing, duplicated, unbounded, stale, or physically unresolved
values fail closed and never redirect to another display.
