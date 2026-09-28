# Normal Mac bundled-native selection — 2026-09-27

The normal Mac application root now forwards a bundled development native backend
factory into its existing dashboard/runtime owner. `MacBundledNativeHostDevelopmentV1`
requires a valid containing-app signature for the existing menu identity, the exact
catalog digest compiled into the app, and a complete matching regular-file host
inventory. Executable locations are fixed within the bundle. Catalogs cannot choose
other executables or supply their own authority. Validation repeats inside the
existing permit-checked factory before backend construction. Missing resources
leave the optional native factory unavailable. Release composition returns no
factory for this development authority.

The normative managed-host specification and indexed admission fixture were updated
first. No pairing, approval, certificate, operation signature, wire route or grant
semantics changed. The development authority is the exact previously tested
production-supervisor package; final release dependency/source admission remains
independent and open.

## Evidence

- Normal Mac Debug build passed with stable Xcode 27.0:
  `/private/tmp/maccompanion-bundled-native-normal-build-final.log`.
- Two focused tests passed, covering missing/unsigned catalogs and changed,
  missing, extra or linked host files:
  `/private/tmp/maccompanion-bundled-native-selection-focused-tests-v3.log`.
  Initial tests exposed macOS directory/path normalization differences; comparing
  consistently standardized directory and file paths fixed the failure.
- `scripts/stage_bundled_native_host_development.py` constructed a fresh signed
  normal app stage without installation, GUI launch or login-service mutation:
  `/private/tmp/maccompanion-bundled-native-normal-stage-20260927-v2.app`.
  Strict nested signature checks and unchanged admitted host bytes passed.
  Log: `/private/tmp/maccompanion-bundled-native-normal-stage-v2.log`.
  The initial staging verification used filename rather than inline requirement
  syntax; the final builder uses the explicit inline requirement form.
- The production selector executed against this actual signed normal app stage
  and returned a native factory:
  `/private/tmp/maccompanion-bundled-native-catalog-probe.log`.
  This exercises resource selection; it does not launch the GUI, Agent, supervisor
  or host and does not prove installed normal-app streaming.

- The Release-compiled production selector refused the same signed development
  catalog: `/private/tmp/maccompanion-bundled-native-catalog-release-probe.log`.
- Required stable repository validation passed, including 109 indexed fixtures
  and the resource rejection tests:
  `/private/tmp/maccompanion-bundled-native-selection-handoff-validation.log`.

Catalog SHA256: `ec578d38801443a6e78d938a4b8de0c6d7be510d8b9afe8fee5810d2a48ebf5d`.
Selected host manifest SHA256: `ea719c8ec6830a838eb97f66c6b0b661031e4f79ff18ae4a9720a73c952a3e2e`.

## Remaining

The installed app is unchanged. Normal iOS adapter admission/selection, signed
normal GUI/session acceptance, intended development requirement/TCC continuity,
installation, real system input, LAN/physical acceptance, App/Window capture and
visible-area bitrate remain open. Earlier Simulator journeys prove their own exact
source/package snapshots; they do not prove this newly added normal-root selector.
The stage is development-only and no release or publication was performed.
