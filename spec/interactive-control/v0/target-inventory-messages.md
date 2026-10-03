# Surface target inventory

Status: normative closed schemas and privacy boundary for the authenticated
application-primary command channel.

The iPhone may request a transient App Focus and Window Focus picker only while
one Interactive Control session is active and its initial Desktop is
acknowledged. Inventory is convenience metadata, not authority. The host
re-resolves the selected opaque token and rechecks the live session, epoch,
source ownership, availability, privacy class, and capture filter immediately
before preparing a transition.

## Exchange

`interactive.surface.targets.request` is an original request with null
`correlationID`. Its body contains exactly `interactiveSessionID`,
`authorizationEpoch`, and the next client surface-control `sequence`.

`interactive.surface.targets.response` correlates to that request. Its body
contains exactly:

- `interactiveSessionID` and `authorizationEpoch`;
- `inventoryRevision`, a positive safe integer scoped to this session;
- `validForMilliseconds`, from 1 through 120,000;
- `candidates`, a sorted unique array of at most 192 candidates; and
- the next server surface-control `sequence`.

The request and response consume the same per-direction sequences used by
initial activation and surface replacement. Only one inventory request may be
in flight. A response does not pause media or input, but selection cannot race
an unresolved inventory response.
An active native video enrollment stays in place while the picker inventory is
requested. The client cancels and drains that enrollment only after the user
chooses a replacement surface and before sending its selection command.

## Candidate schema

Each candidate contains exactly:

- `targetToken`: random UUID valid only for the current inventory revision;
- `kind`: `application` or `window`;
- `applicationToken`: the application candidate token that groups the entry;
- `applicationName`: locally supplied display name, 1 through 128 UTF-8 bytes,
  with no control, line-separator, or paragraph-separator scalar;
- `windowOrdinal`: null for an application or an integer from 1 through 64 for
  a window;
- `windowTitle`: null for an application or an untitled window, otherwise a
  presentation-only title of 1 through 128 UTF-8 bytes without control,
  line/paragraph separator or bidirectional formatting scalars; and
- `currentWindowAvailable`: a Boolean snapshot fact.

Candidates are sorted by Unicode-scalar application name, then application
before window, then window ordinal, then canonical target token. Names are
presentation only and never used to resolve or authorize a target. Tokens are
unique, unpredictable, and regenerated for every inventory revision. A window
candidate's `applicationToken` must identify an application candidate in the
same response. An application candidate uses its own `targetToken` as
`applicationToken`.

The initial inventory intentionally carries no icon bytes. A later bounded,
content-type-checked icon exchange may be added independently; its absence does
not permit thumbnails or window content to substitute as icons.

## Privacy and lifetime

The inventory may derive the localized application name, grouping, and bounded
window title from ScreenCaptureKit running-application/window relationships.
Titles are transient metadata for the authenticated device's active Control
picker only, and may include document names already visible in that window.
The menu normalizes whitespace, removes control and bidirectional formatting
scalars, and truncates at a character boundary to 128 UTF-8 bytes. Titles never
enter audit, diagnostics, persistent stores, Observe or Act. No additional
document/path/URL/Accessibility query may enrich them. The inventory must not
read, transmit, log, or persist:

- thumbnails;
- bundle identifiers, process IDs, Core Graphics window IDs, or ScreenCaptureKit
  object identity;
- document paths, URLs, recent-document metadata, or workspace names;
- Accessibility labels, descriptions, identifiers, values, selections, text,
  placeholders, or hierarchy; or
- Mac Companion administration, permission, login, lock, credential, or other
  excluded security surfaces as ordinary candidates.

The menu grants a 120-second picker interval by default so a person can
inspect and scroll a full inventory before selecting. The host still checks
the current source, ownership, exclusion policy, and capture filter at the
moment of selection; an inventory entry alone grants no capture authority.

Host-local source references remain inside the visible menu-app inventory
owner. Inventory expires on its half-open local monotonic deadline and is
invalidated on refresh, selection preparation, source disappearance or
ownership change, lock, authorization-epoch change, selected-display change,
menu-app/Agent IPC loss, suspension, or session end. No token survives restart
or crosses Interactive sessions.

## ScreenCaptureKit resolution

Desktop resolves to the already selected `SCDisplay`. Application resolves to
an `SCContentFilter` for that exact selected display and exact current
`SCRunningApplication`, with no client-controlled exclusions. Window resolves
to a desktop-independent filter for the exact current `SCWindow`. Immediately
before filter construction, the owner requires the mapped object to still
belong to the same observed application, remain on-screen and non-empty, and
remain outside the exclusion policy.

Only on-screen layer-zero windows with finite bounds and a supported profile
of at least 320 by 240 encoded pixels are ordinary picker targets. Applications
without these windows are omitted. Application view availability requires a
supported app-only crop on the selected display; independent Windows may live
on another active unrotated display. The client omits unavailable choices and
uses an app name plus ordinal only when a window has no usable title.

An exactly bound, consumed App/Window token whose source has disappeared or
become uncapturable may resolve a fresh Desktop replacement on the already
authorized selected display. This explicit response says Desktop, advances both
revisions once, and contains no app/window/focus token. Stale, unknown, expired
or wrong-kind tokens, principal/fence mismatch and excluded sources do not
qualify. Local and client receipt validators accept this Desktop replacement;
clean-frame acknowledgement still precedes input.

The resolver never falls back silently when a token is stale or ambiguous. It
returns a closed source-unavailable result that cannot authorize fallback.
Only the consumed, exactly bound disappeared-source case described above may
produce the explicit Desktop replacement. Focused-region
resolution remains a separate Accessibility/crop contract and is not inferred
from an app/window candidate.
