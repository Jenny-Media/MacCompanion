# One-shot prepared-installer reply

Date: 2026-08-23

Status: package behavior, permanent-app source policy, and compile composition
pass on Xcode 27 beta. No app, Agent, listener, local-XPC service, login role,
TCC surface, network connection, Sparkle download, or installer was started.

## Outcome

`MacUpdatePreparedInstallerReplyOwnerV0` is the single-use bridge between the
runtime shutdown coordinator's final `startPreparedUpdate` effect and a held
updater reply. The main-actor owner consumes its reply before emitting install,
rejects a second start, makes repeated cancel harmless, and emits skip if a
pending owner is explicitly cancelled or retired.

The permanent Sparkle adapter constructs this owner only inside the
post-validation ready callback and maps its closed install/skip values to the
corresponding Sparkle choices. The existing inert path still cancels the
package correlation and reply owner. It does not construct a runtime shutdown
coordinator and cannot call the install effect.

The permanent-target source policy admits exactly one `reply(.install)` token,
only in the adjacent install-to-install and skip-to-skip mapping. It rejects a
second install token, a substituted mapping, any direct app invocation of
`startPreparedUpdate`, full or background checks, automatic downloads, and a
generic updater surface.

## Verification

Four focused tests cover exact-once install, post-install cancel, second-start
rejection, explicit cancel idempotence, pending-owner retirement to skip, exact
shutdown ordering, and post-stop installer failure recovery. The complete
repository gate passes 73 authoritative fixtures, 35 update-policy fixtures,
every supply-chain, privacy, SBOM, signing, packaging, release-evidence,
permanent-target, and cross-platform validator, 1,598 MacCompanionKit tests,
and 8 platform-probe tests on Xcode 27 beta.

## Deliberate non-claims

No full update check can reach the ready callback in the permanent app. This
checkpoint does not present foreground confirmation, call
`reachedReadyToInstall`, construct the runtime coordinator, mutate listener
admission, stop or recover the Agent, or exercise Sparkle installation. Signed
two-version execution, forced process loss, stable Xcode 26.6 repetition, and
the final foreground/runtime owner remain release gates.
