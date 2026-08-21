# Opaque target catalog construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package only

## Scope

This evidence covers the privacy-limited App Focus and Window Focus target
inventory, authenticated command routing, client-local expiry, and
compile-checked ScreenCaptureKit filter construction. It performs no content
enumeration, capture, permission request, or input posting.

The menu-owned catalog:

- exposes only random session/revision-scoped tokens, localized application
  names, generic window ordinals, and current-window availability;
- keeps bundle identifiers, PIDs, window IDs, and ScreenCaptureKit objects
  inside the catalog and never reads window titles;
- requires explicit menu/Agent self-exclusion before construction;
- consumes the complete inventory on selection and rechecks live application
  ownership, on-screen state, non-empty geometry, exclusion policy, and the
  selected display;
- creates the exact selected-display application filter or exact
  desktop-independent window filter; and
- produces an exact +1 replacement descriptor without granting new interaction
  classes.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

Result: 51 indexed fixtures validated; all 544 Swift tests passed; both
Network-platform targets and all three no-prompt/no-network probes compiled;
`git diff --check` passed.

## Boundary not claimed

This is construction and injected/pure evidence, not physical Screen Recording
evidence. Final signed menu/Agent identities, authenticated XPC admission,
actual `SCShareableContent` enumeration, live filter-to-stream replacement,
multi-display/window churn, and clean-media visual verification remain required
before this can count toward a usable alpha.
