# Interactive Control initial runtime preparation v0.1

Status: normative for bundle-independent first-lease construction and install-receipt consumption. Authenticated XPC transport and the atomic final admission/install implementation remain platform work.

## Authority input

The preparation authority consumes exactly one verified
`InteractiveSessionBootstrap`, the final
`InteractiveSessionRuntimeRequirementV0`, and one sanitized initial Desktop
descriptor. The bootstrap must be in `starting`, and its session ID,
authorization epoch, and retained signature-bound approved effects must equal
the descriptor and requirement. The final requirement must satisfy the same
closed eligibility predicate as request/proof admission and retain a nonzero
visible-menu-app generation/revision plus selected display.

The Desktop descriptor must be current at the local monotonic preparation
sample, use revision 1 for both surface and coordinate space, contain no
Desktop-forbidden metadata, and expose exactly—not a subset or superset—the
approved interaction classes. The Agent takes this preparation sample only
after the correlated menu-prepared descriptor returns and final admission is
revalidated. It MUST NOT reuse a sample taken before the cross-process
descriptor request, because the menu creates the descriptor against a later
host-monotonic sample.

A failed attempt before first-lease installation may leave only a prepared
menu-side Desktop descriptor. A later fresh session may replace that unleased,
non-authorizing descriptor; it may never replace an installed lease or an
in-progress surface transition.

Termination of the exact session and primary connection must fence a pending
install immediately, before waiting for serialized cleanup or surface-control
work. Runtime binding and scheduling wrappers must forward this fence without
queuing it behind the install it cancels. Every awaited preparation/admission
result must recheck the retained install token before issuing the first lease.
A stale session/connection termination cannot fence a replacement. If install
was already sent when termination arrives, its late receipt requires normal
four-effect revocation and must not publish active authority or role credentials.
The renewal owner also retains this exact install token across its awaited
active-lease lookup. A lookup returning after termination cannot start a timer
or renew an ended session, even if its returned lease was previously valid.

## First lease and command

Preparation is one-use. It creates fresh command and lease IDs supplied by the
product's OS-random identifier source and issues renewal counter zero. The
lease binds the exact host, device, session, authorization epoch, selected
display, initial surface IDs/revisions, and approved classes. Its expiry is the
earliest of ten seconds after issue, the four-hour session deadline, and the
Desktop descriptor deadline. Overflow, an already expired bound, or a reused
authority fails before any command is released.

The resulting `InteractiveRuntimeInstallCommandV0` carries the locally
confirmed device name, Desktop, and the same session deadline. Exact replay of
the same prepare inputs returns the same command; conflicting reuse fails.

## Receipt and transfer

An install receipt is accepted only while the prepared lease is current and
only when its command/lease/session/display binding, indicator, and ready
classes validate. Its menu-app generation must equal the admitted generation,
and its revision must be at least the admitted revision. Another generation or
an older revision is teardown-required, not retryable success.

Successful receipt consumption advances the retained session from `starting`
to `activeUnlocked`. The installed bootstrap, including both role credentials,
can then be transferred exactly once to the Agent runtime owner; it is never
returned as a copy while still retained by the preparation authority. A
mismatched or late receipt invalidates unused role credentials and enters
`teardownRequired`, because the menu runtime may have installed effects even
when the reply cannot be trusted.

This authority does not perform final durable admission or menu installation.
The future signed runtime bridge must serialize that final re-read with the
authenticated XPC install and must drive four-effect teardown whenever this
authority reports `teardownRequired`.
