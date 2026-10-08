# Mac dashboard Control composition after local XPC replacement (2026-09-28)

The normal Mac dashboard already replaces its one-shot local-XPC product when
the authenticated Agent connection becomes unavailable. That replacement
previously reused the process's Control runtime adapter, native-admission gate,
media queue, and capture target owner. Agent-IPC invalidation closes the old
adapter's native-admission gate and invalidates its capture targets, so a new
connection alone could not safely provide a fresh native Control session.

The dashboard now withdraws the old receiver and awaits the old adapter's
runtime invalidation before creating the replacement product. Its permanent
composition creates a fresh runtime, queue, input adapter, capture target
owner, and local native-admission gate for the replacement connection. The
process-lifetime activity indicator and selected display identity remain
owned by the dashboard. If cleanup leaves that indicator active or stopping,
the replacement has no Control runtime. The new connection still publishes
revision 1 under the existing process menu UUID and requires a fresh
Agent-issued Control lease; pairing and durable grants are not recreated.

The recovery ordering is specified in
`spec/interactive-control/v0/menu-runtime-composition.md` and the indexed
`local-xpc-interactive-admission-transport-v0.1.json` fixture. Two focused Mac
package tests pass: the replacement factory waits behind the cleanup barrier,
and separate composition constructions own distinct runtime, queue, and
capture-target objects. Logs:

- `/private/tmp/maccompanion-dashboard-recovery-barrier-20260928.log`,
  SHA-256 `e5120db8a48a20debb594062539486287ef7af51dbbdf960594b5fb2a03baa9d`.
- `/private/tmp/maccompanion-dashboard-fresh-composition-20260928.log`,
  SHA-256 `e34b1a5cb84d7d98757211988702947625880e94cd65d7e31cb34be2c3519e25`.

The paired iOS Simulator recovery journey currently uses a replacement
disposable signed Mac menu, not this dashboard.

## Installed development checkpoint

Stable `bash scripts/validate.sh` passed with 116 indexed fixtures. Log:
`/private/tmp/maccompanion-validate-dashboard-recovery-final-20260928.log`,
SHA-256 `faac410c37895f55b21115643b6469039d23475609a8fef34faf249e023f17a2`.
The normal Mac Debug app built successfully from this source. Its signed
development staging matched the compiled native-host catalog SHA-256
`e6a46019ecbd18104400ef5a1891f05691029c1cb547bbcb44def70c7a67bb8f`
and passed strict containing-app signature verification. The prior installed
app was saved with a byte-identical 278-entry inventory and valid signature
under `/private/tmp/maccompanion-dashboard-recovery-preinstall-20260928.app`.

The updated app is installed at `~/Applications/Mac Companion.app`, and its
containing signature verifies after installation. The installed dashboard
launched. Its supported `maccompanion://repair-agent-registration` command
restored the already enabled ServiceManagement Agent after the installation;
launchd reports the Agent running and its loaded executable resolves inside
the updated installed bundle. The separate Sunshine installation was not
changed. The app's visible dashboard state and a post-reconnection native
Control session have not yet been observed, so this checkpoint does not claim
installed recovery or playback acceptance. A direct launchd bootstrap attempt
returned error 5; the app's own registration repair succeeded.

One controlled termination of the registered Agent changed its PID from
95798 to 98097 while the installed dashboard remained running at PID 94627.
ServiceManagement launchd reports the Agent running with `runs = 2`. This
proves process restart and containing-app survival; no client Control request
was made during that test, and the dashboard's replacement runtime was not
observed directly.

The next [installed recovery checkpoint](2026-09-28-agent-entitlement-preservation-and-installed-recovery.md)
found that this staged Agent had lost its Keychain entitlement. After correcting
the development staging signature, the installed dashboard visibly recovered
its ready/listening state across a controlled Agent restart.
