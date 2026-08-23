# Foreground update-installation owner

Date: 2026-08-23

Status: package behavior and compile composition pass on Xcode 27 beta. No app,
Agent, listener, local-XPC service, login role, TCC surface, network connection,
Sparkle download, or installer was started.

## Outcome

`MacUpdateInstallationApplicationV0` now owns the presentation lifecycle for
one already admitted and prepared update. The only public composition factory
constructs its runtime coordinator around the exact same one-shot prepared-
installer reply owner, preventing reply substitution between presentation and
shutdown.

The main-actor lifecycle begins awaiting confirmation and permits one path to
confirming, installing, and handed off. Explicit cancellation or foreground
loss before installation resolves skip and closes the authority. Foreground
loss during shutdown is forwarded to the package authority, whose next
boundary fails and invokes the minimum recorded network-only or Agent-plus-
network recovery. Owner retirement also resolves any pending reply to skip and
cancels unresolved authority.

Presentation failures are closed and content-free: authority denied, Control
active, Control cleanup uncertain, runtime effect failure, recovery failure,
or invalid state. They expose no Sparkle, Agent, candidate, transport, or raw
error object.

## Verification

Four focused tests prove exact one-time confirmation and handoff, cancellation
and owner-retirement closure, Control-active denial, pre-stop effect recovery,
and foreground loss while confirmation is suspended. The race test verifies
that skip is emitted before the suspended observation resumes and that no
network or Agent effect can subsequently start. The complete repository gate
passes 73 authoritative fixtures, 35 update-policy fixtures, every supply-
chain, privacy, SBOM, signing, packaging, release-evidence, permanent-target,
and cross-platform validator, 1,602 MacCompanionKit tests, and 8 platform-probe
tests on Xcode 27 beta.

## Deliberate non-claims

The permanent Sparkle adapter does not yet construct this application, present
its confirmation UI, or forward NSApplication foreground events. No full
update check can reach the prepared hold point. Signed two-version execution,
forced process loss, stable Xcode 26.6 repetition, and physical confirmation
UX remain release gates.
