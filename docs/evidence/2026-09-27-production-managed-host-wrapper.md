# Production managed-host wrapper promotion — 2026-09-27

## Scope

The first-party process owner and isolated loopback enrollment backend now live
in `CompanionMacApplicationPlatform` as `MacManagedSunshineProcessOwnerV1` and
`MacManagedSunshineEnrollmentBackendV1`. Their experimental files are compatibility
aliases to the production module. The finite C supervisor moved unchanged into
`Native/Host/companion-supervisor.c`; test builders use an explicit macOS 26 target,
and source inventory/export includes its new location.

`MacManagedSunshineBackendFactoryV1` joins the approved physical display, capture
geometry and menu-owned permit. It requires an explicit trusted local artifact
validator, checks the permit before and after that validator, and forwards the
atomic input permit. The normative managed-host document and indexed fixture
were updated before implementation. The Mac-only privacy source inventory now
records the promoted file metadata checks. No authentication or pairing algorithm
changed.

The signed lab delegates to this production factory, after the outer runner's
package/signature validation and an exact executable digest check at construction.
The normal release roots still need their admitted artifact selection; foreign
binaries and experiment modules were not added to permanent targets.

## Verified evidence

- Real process-owner checks passed: denied, expired and overlong admission,
  original four-hour deadline, live revocation, terminal ownership, concurrent Stop.
  Log: `/private/tmp/maccompanion-production-process-owner-tests.log`.
- Four real supervisor tests passed from the new production source path.
  Log: `/private/tmp/maccompanion-production-supervisor-tests.log`.
- The normal Mac app's unsigned Debug build passed with stable Xcode 27.0.
  Log: `/private/tmp/maccompanion-production-host-wrapper-normal-build.log`.
- The iPhone SDK component rebuilt successfully. No physical device was accessed.
  Log: `/private/tmp/maccompanion-production-wrapper-iphone-sdk-build.log`.
- Signed LaunchServices app test passed all four cases, actual native HTTPS launch,
  two lease renewals, Stop/Observe and cleanup. The temporary app matched the
  installed development designated requirement; the installed app was unchanged.
  Report: `/private/tmp/maccompanion-agent-xpc-evidence.f61ff_a7/native-report.json`.
  SHA256: `33d3d26e9abe87d49c0a29b00b9d7155ffbdd877bc03af33aa7c311d6232f269`.
  Native source input: `f1823c16edc7cf6126932a6d94f8106ee76d0f65fdc885bfd4ffc8e553311d07`.
  This run used the previously verified portable package, including its previously
  built supervisor; it does not claim that the new macOS-targeted supervisor binary
  has been repackaged or admitted.

- Both factory admission tests passed: rejected artifacts and Control revocation
  during validation prevent backend construction. Stable `bash scripts/validate.sh`
  passed (109 indexed fixtures plus package/platform suites).
  Log: `/private/tmp/maccompanion-production-host-wrapper-validation-final.log`.
  The initial run stopped at the promoted privacy inventory mismatch; the final
  run includes its corrected Mac-only inventory.
- All six native frameworks pass the refreshed source-bound candidate inventory.
  Log: `/private/tmp/maccompanion-production-wrapper-candidate-inventory.log`.

- The native Simulator journey passed one XCTest with four visible native
  sessions: keyboard/modifiers/shortcuts/pointer, background revocation,
  route-loss recovery, explicit restart, Stop/Observe and cleanup. Actual final
  input effects remain synthetic. The loopback Mac test parent is command-line;
  the separate app-owned test above supplies the LaunchServices ownership check.
  Report: `/private/tmp/maccompanion-agent-xpc-evidence.pyh9c8lr/signed-simulator-report.json`.
  SHA256: `f0ea5b4846c17bfe71ebcf3babd62b7bff34a5932acc4c3d9f0702a0cc7bdd86`.
  Simulator: `B3EE3E69-C172-4198-8E88-7CBDDAC5BB55` (iPhone 18 Pro Max, iOS 27.0).
  Combined source SHA256: `f732b8d0196da640bf014774ae044129282b8fff46e0ac039e8834b2e8fe4da1`.
  All four captures: physical 5120x2134, logical 2560x1067, encoded 1920x800.

## Limits and next work

This is production first-party code with development acceptance. Default native
factories are still unset. Signed normal-app resource/dependency/signature
selection, the final packaged supervisor, real system input, installation,
LAN/physical acceptance, App/Window capture and visible-area bitrate remain open.
The source-delivery packet and native candidate inventories from earlier turns
remain historical snapshots. Simulator testing uses synthetic final input effects
and isolated test custody; it does not prove actual Mac input or phone installation.
