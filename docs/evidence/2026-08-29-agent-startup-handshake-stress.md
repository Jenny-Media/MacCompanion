# Agent startup and menu-handshake stress checkpoint

Date: 2026-08-29
Status: passed for the disposable signed pre-physical boundary

## Outcome

Two independent final runs completed 200 consecutive signed Agent startup
cycles with no timeout, retry, skip, or cleanup failure. Each run used one new
UUID-scoped launchd service, a mode-0700 temporary state root, copied Debug
helpers signed with their exact Agent/menu identifiers, and the unchanged
ten-second readiness deadline.

Each run executed 25 cycles of all four valid startup shapes:

- normal enabled startup through `probe-entered`, `startup-preparing`, and
  `service-running`;
- deliberately slow status startup through the same readiness markers;
- production-primary composition through persisted software identity reload
  and `service-running`; and
- production-presentation composition through the private listener, signed
  menu authentication, generated review delivery, QR create/dismiss retry,
  no-device grant rejection, verified status, `presentation-cycle-complete`,
  `service-running`, and graceful shutdown.

The enabled durable intent is established once per run through the signed
bootstrap protocol. The runner does not write an enabled fixture directly.
This is required because a presentation launch while the durable intent is
disabled correctly selects the disabled bootstrap path.

## Exact results

Both reports bind Agent/XPC source fingerprint
`24dc4e02ff01b49687b9502790297a80228fdfa43c1bacef43765300f95e0620`
and runner hash
`1e158400ffa23f653739d86907df7f4bd19fc3bd5601f006ef4aabbba5e74f43`.

| Run | Cycles | Maximum normal | Maximum slow | Maximum primary | Maximum presentation + handshake | Cleanup | Report SHA-256 |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `/private/tmp/maccompanion-agent-xpc-evidence.hvdiceqe/startup-stress-report.json` | 100 | 0.1417 s | 0.1394 s | 0.1357 s | 0.3830 s | verified | `37525926ec0c9bcfcac1effa320ba7f890a618cebe296867cc9f630e1f52bb67` |
| `/private/tmp/maccompanion-agent-xpc-evidence.mlnmz92f/startup-stress-report.json` | 100 | 0.1411 s | 0.1318 s | 0.1397 s | 0.3266 s | verified | `f826f480d3c74a34850a365b5ec7ab1ab29df0f86cde21d2cc7cdceb7af50738` |

Independent post-run checks found both exact launchd labels absent and both
temporary state roots absent. The reports contain all 100 per-cycle durations,
mode-specific server/client markers, graceful-shutdown facts, exact test IDs,
source hashes, and limitations.

## Historical finding disposition

The two earlier pre-output launch timeouts and one signed-menu timeout remain
retained as failed historical runs. Their causes were never established, so
this checkpoint does not rewrite them as successes or claim a causal repair.
They occurred on older source fingerprints before the final integrated Agent
and Simulator checkpoint.

They are no longer a known current required-path defect: the current source
crossed the exact pre-entry, preparation, readiness, signed-menu handshake, and
graceful-shutdown boundaries 200 consecutive times under an unchanged
deadline. Any future timeout still fails immediately and preserves the exact
launchd job state plus a one-second stack sample of only the disposable PID.
This closes the P6/P8 startup reliability gate while keeping the old failures
available as provenance.

## Boundaries

The test uses software identity custody and loopback/private XPC only. It does
not use the installed Mac app or Agent, SMAppService, production Keychain/TCC,
LAN/Bonjour, Simulator, or a physical iPhone. It is beta-toolchain reliability
evidence, not stable-toolchain release certification or installed lifecycle
proof.
