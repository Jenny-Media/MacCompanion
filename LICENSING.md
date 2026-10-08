# Mac Companion licensing

Decision date: 2026-09-26.

Mac Companion's combined product distribution uses GPL-3.0, following the
owner's decision to build the Mac server on Sunshine and the iOS streaming
client on Moonlight. New Mac Companion contributions use GPL-3.0-only unless
a file states otherwise. The complete GPL version 3 text is in `LICENSE`.

Existing code previously offered under Apache-2.0 retains that permission and
its applicable notices; adopting GPL for a combined distribution does not
withdraw rights already granted to that code. The preserved Apache text is in
`LICENSES/Apache-2.0.txt`. Retain file-specific licenses and upstream notices.
Third-party components are governed by their own terms, including any
GPL version-selection permissions, permissive licenses, and exceptions.

Sunshine and Moonlight source is initially fetched into isolated experiment
checkouts, not silently admitted to permanent application targets. Each source
revision, submodule, patch, and bundled library must be inventoried before
product distribution. Adding the GPL text does not complete that review.

Every distributed covered binary must be accompanied by an applicable GPL
corresponding-source delivery arrangement, including the source, patches,
dependencies and build/install scripts required by the license. Release
packaging must produce and verify that source artifact against the exact
binary candidate. Signing credentials and private user data are not source
artifacts and must never be included.

Commercial distribution is permitted subject to the licenses. The intended
Apple distribution channel and any additional distribution terms require
review before external release. Source availability grants no Jenny Media
trademark, official signing, update-channel, or Apple entitlement authority.
See `NOTICE`, `TRADEMARKS.md`, `CONTRIBUTING.md`, and `SECURITY.md`.

This decision supersedes earlier Apache-only product licensing plans. It does
not reopen external contribution intake or authorize publication by itself.
