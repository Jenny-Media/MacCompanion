# Pre-physical automated gate checkpoint

Date: 2026-08-29

## Outcome

All currently runnable short-duration pre-physical paths pass against the
current source. The only time-dependent automated gate is the real seven-date
soak, which remains at Day 1 and is being continued by the active daily task.
No physical iPhone, installed production app/Agent, production Keychain/TCC,
user content, external account, upload or publication was used.

## Integrated evidence

- Three final signed Agent + Simulator runs passed the complete pair, reconnect,
  Observe, bounded Act, Control, media, input, adaptive UX, Stop and recovery
  journey with shared fingerprint
  `7e10132d98004124bdb13cc176edfda9ab708abbc5b3363fd67c4092b40e192c`.
  Durations were 113.582, 112.485 and 115.060 seconds; cleanup passed.
- The complementary signed isolated Agent/XPC matrix passed 55/55 with cleanup,
  including graceful/crash restart, signed administration, revocation,
  final-admission races, menu loss and revocation during preparation.
- A dedicated current-source reliability gate passed two independent 100-cycle
  signed Agent runs under the unchanged ten-second deadline. All 200 launches
  crossed mode-specific readiness; 50 production-presentation cycles completed
  the signed menu handshake and graceful shutdown. Exact cleanup passed. This
  retires three older launch/handshake timeouts as historical failures without
  asserting an unknown cause; see the
  [stress checkpoint](2026-08-29-agent-startup-handshake-stress.md).
- The final generated full Simulator gate passed 16/16 with zero failures,
  skips or expected failures in 910.204 seconds. Three generated live and three
  signed test-owned-window live repetitions also passed.
- The final repository validation passed 1,769 Swift tests across 42 runs plus
  fixture, dependency, privacy, SBOM, release, signing, packaging, update,
  rollback, production-build and eight platform checks. Its retained temporary
  log hash was
  `613df08c4da77915fcaedf07831bffc81675629c8deb6c14b0333d825bd459a3`
  (340,700 bytes); the inventory included 1,315 repository files, 78 indexed
  JSON fixtures and 14 repository-material fixtures.
- Construction-only release evidence validated for version 0.1.0 build 1. It
  intentionally has no artifacts, executables, notarization, SBOM promotion,
  physical scenarios or promotion decision and is not a signed candidate. The
  regenerated manifest hash is
  `cb3790fbe7e74e8ef30e8131b02e7b0350263fa128c83aa403c05ded651f8c98`;
  its validation record binds the exact log hash above.

## Resource baseline and performance boundary

[`prephysical-performance-baseline.json`](prephysical-performance-baseline.json)
is bound to the same tested-source fingerprint as the active soak campaign:
`2c19bbba9659d510a4ceab5eda57b4812ce05955c2d9948b034387fd4807f0c0`.
Its generated Simulator soak passed for 199.018 seconds. One-second `ps`
snapshots observed the disposable Mac host 219 times (4.757% mean, 8.4% maximum,
36.156 MiB maximum RSS) and the Simulator client 178 times (10.386% mean,
195.7% maximum, 387.281 MiB maximum RSS). These values include Debug/XCTest
launch and Simulator overhead; they are a reproducible diagnostic baseline,
not release budgets or physical energy evidence.

The existing specifications retain their actual healthy-LAN latency gates:
2.5-second p95 first frame, 300-ms p95 glass latency, 350-ms p95 pointer
response, 1-second p95 app/window keyframe, 300-ms p95 focus-to-zoom, 500-ms
p95 fallback and 3-second p95 Observe reconnect. Physical measurement remains
required. Numeric CPU, memory, energy, battery, network and store-growth
allowances were never set in Stage 0A. The closed
[`performance-acceptance` profile](../../spec/performance-acceptance/v0/README.md)
now makes those and the other unresolved pairing/text measurements eight exact
`requiresPhysicalMeasurementAndApproval` decisions. It also machine-checks the
10 existing latency gates, 7 media caps, durable caps, source-bound soak and a
32-MiB/1-MiB-per-minute one-hour RSS growth gate. Promotion must resolve the
eight decisions rather than infer success from this Simulator observation.

## Remaining gates

- The active ledger has one of seven required distinct UTC dates and zero of
  the required 518,400 elapsed seconds. Six later dates and real elapsed time
  cannot be compressed into this checkpoint.
- Stable Xcode 26.6, explicit distribution custody, signed/notarized archives,
  Apple persistent-capture disposition, final release evidence and publication
  are external or separately authorized work.
- Face ID/Secure Enclave, real LAN/private routes, installed lifecycle,
  production permissions and key custody, user-owned app behavior, actual mute,
  lock/sleep/logout, physical latency/energy/thermal behavior, clean update and
  removal require hardware and are consolidated in
  [`../physical-acceptance-checklist.md`](../physical-acceptance-checklist.md).
- The automated security gate is complete, but an independent review remains
  intentionally unperformed because the active goal did not enable reviewers
  or subagents.

The project is therefore ready for unattended continuation of the soak, not
yet ready to begin physical acceptance or claim the goal complete.

The later [machine-checked completion audit](2026-08-29-prephysical-completion-audit.md)
confirms that this is a complete inventory: it binds the unchanged soak source,
requires all P rows and evidence paths, and rejects any unresolved automatable
required-path failure. Installed-product operation is truthfully classified as
requiring fresh authority, not as inherently requiring an iPhone.
