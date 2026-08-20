# Mac Companion Execution and Blocker Ledger

Status date: 2026-08-19

This is the living execution authority for the staged plan. A blocker applies only to work that names it as a dependency. Work in every other safe lane continues. Evidence links point to repository artifacts or reproducible commands; secrets and Apple-account records remain outside the repository.

## Status vocabulary

- `active`: work can proceed now.
- `ready`: prerequisites are satisfied and work is queued.
- `blocked-external`: an external approval, account value, machine, or user decision is required.
- `blocked-design`: a normative decision must be reconciled before implementation.
- `passed`: exit evidence is recorded.
- `no-go`: evidence rejects the capability for the supported product.
- `deferred`: the capability remains optional and has a recorded reason and re-entry condition.

## Current lanes

| Lane | Stage | Status | Current evidence | Blocker or next proof | Independent work that continues |
| --- | --- | --- | --- | --- | --- |
| Design baseline | 0A | active | Reconciled product documents plus ledger, ADR, threat model, and permission matrix; three-agent audit; `git diff --check` | Commit one baseline revision | All read-only research and reconciliation |
| Protocol trust kernel | 0B | active | Architecture and protocol outline | Freeze v0 envelope, bounds, state machines, pairing transcript, epochs, errors, and fixtures | Pure Swift domain/wire/security packages and conformance tests |
| Apple identifiers | 0A | blocked-external | Jenny Media LLC is the intended team; placeholder IDs are documented | Confirm Team ID and company-controlled reverse-DNS prefix | Specifications, packages, CI, ADRs, disposable experiments |
| Persistent capture request | 0A | blocked-external | Apple managed-capability process and intended final Mac App ID are documented | Create final App ID, then Account Holder submits request and records request ID privately | Observe, protocol, lifecycle, ordinary-consent capture experiments |
| Stable release toolchain | 0A | blocked-external | `xcode-select` points to CommandLineTools; only Xcode 27 beta is installed; no valid signing identity was observed | Provide a stable macOS 26 build/test Mac with Xcode 26.6 and signing custody | Pure Swift work and beta-toolchain disposable harnesses |
| Process and local IPC | 0A | active | Architecture boundary; ADR-0001 | Select and prove audit-token/designated-requirement checks on final identities | Interface design and invalid-peer test vectors |
| Capture/input feasibility | 0A | ready | Menu app owns TCC-sensitive work; agent owns policy/network | Run separate Screen Recording, Accessibility observation, and post-event probes; record lock result | Harness design can use beta Xcode; final TCC attribution waits for IDs |
| App Review | 0A/3 | active | 4.2.3(i), 4.2.7, companion-app, LAN wording, and system-picker risks are recorded | Prepare an honest LAN-first external TestFlight review package | Internal builds and product evidence plan |
| Observe alpha | 1 | blocked-design | v0 trust kernel and release-shaped lifecycle are unfinished | First physical Mac/iPhone `status.snapshot` with revocation | Domain, fixtures, status sampling, client presentation models |
| Adaptive Control | 2 | blocked-design | Interactive drafts exist, but identity/revocation and platform experiments are unfinished | Final grants/epochs plus physical latency and safety evidence | Media/input schemas and pure state machines |
| No-relay beta | 3 | deferred | Route-independent identity is a fixed requirement | Stages 1 and 2 must pass; external review strategy required | Provider-neutral diagnostics design |
| MacTools/provider work | 4 | deferred | Paper compatibility map only | Market-MVP repeat-use gate | No bridge implementation before the gate |
| Semantic/native surfaces | 5 | deferred | Safety boundary documented | Market-MVP evidence and one validated job | No semantic authority inferred from Accessibility data |
| Administrator capabilities | 6 | deferred | Each capability is independent | Separate demand, threat model, containment, and review per capability | Each item receives its own pass/no-go/deferred record |
| Assisted operation | 7 | deferred | Untrusted-planner boundary documented | Earlier gates plus one validated assisted job and injection review | No model receives control authority implicitly |

## Immediate milestone

Deliver the bundle-independent v0 trust kernel:

1. Freeze the reconciled operation, device, session, grant, suspend, and revocation state machines.
2. Publish normative envelope, bounds, stable errors, `session.describe`, and `status.snapshot` schemas.
3. Make `spec/fixtures` the single valid and invalid fixture authority.
4. Build pure Swift `CompanionDomain`, `CompanionWire`, `CompanionSecurity`, and test-support targets.
5. Prove legal and illegal transitions, stale-epoch denial, canonical decoding, malformed bounds, and fixture parity in public unsigned CI.

## Blocker handling rule

Every blocked item records its affected artifact, evidence needed to unblock it, and parallel work. The project is not globally blocked while any safe in-scope lane remains active or ready. A later-stage capability is complete only with passing exit evidence or an explicit evidence-backed `no-go` or `deferred` disposition.
