# Stage 2 candidate worktree audit

Date: 2026-08-29

Status: implementation organized and repository validation passing; signed
candidate construction and candidate-bound physical acceptance remain open.

## Starting state

The audit began on `main` at `8a49297d707971c37d2fb93fbd20df6b12d6d654`
with no staged changes. The accumulated working tree contained 223 tracked
changed paths and 92 untracked paths. The tracked diff contained 14,582
additions and 1,040 deletions. One apparent fixture deletion was an intentional
move from `invalid` to `valid` after the protocol made ordinary keyboard text
legal without a focused Smart Input field.

Repository material validation found no committed or untracked signing keys,
certificates, provisioning profiles, credentials, private user content, or
generated build products. `git diff --check` passed before organization.

## Implemented Stage 2 boundary

The audited implementation includes:

- independently authorized Observe, Act, and Control paths;
- named multi-device administration with up to eight retained paired clients
  and one active remote session at a time;
- explicit local capability-grant review and revocation;
- production TLS, application authentication, Agent/menu XPC, lease renewal,
  final admission, shutdown, and reconnect recovery;
- Desktop, App Focus, Window Focus, focus-assisted Smart Zoom, user-overridden
  visual zoom, trackpad/direct-touch interaction, ordinary iOS keyboard,
  native composer, modifiers, shortcuts, and real double-click state;
- in-session Shared Display selection through fail-closed surface replacement;
- bounded H.264 capture, encode, transport, decode, render, and input paths;
- signed disposable Agent/XPC and authenticated Simulator journeys plus
  startup, fault, lifecycle, performance-profile, and cleanup validators.

The implementation does not claim a relay, shell, files, clipboard, audio
streaming, unattended pre-login control, simultaneous active clients, or a
multi-display composite surface.

## Organization

The previously accumulated implementation was separated without discarding or
rewriting user work:

1. `c64cca4` — Stage 2 product, protocol, fixtures, package tests, permanent
   targets, acceptance profile, and core product/specification documents.
2. `a03f184` — signed Simulator, Agent/XPC, real-window lab, soak/reporting
   tools, safety tests, and repository validation integration.
3. The roadmap, historical checkpoints, superseded-soak audit, and this audit
   remain together in the following evidence commit.

## Validation and repaired defect

`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash
scripts/validate.sh` first exposed two truthful blockers:

1. The retained one-day pre-physical campaign was bound to older source. The
   completion validator now accepts it only as `supersededSource`, requires the
   exact historical campaign still to exist, and makes no current-readiness
   claim. It cannot be rebound or resumed for the candidate.
2. The Live Control Lab still called a removed single-device store API. The
   disposable journey now retains the device identity authenticated in that
   journey and revokes that exact device instead of restoring a production
   single-device assumption.

The focused Live Control Lab build and all eight safety tests passed after the
repair. The complete repository validator then exited successfully, covering
indexed fixtures, material and dependency policy, release construction,
privacy, signing/notarization parsers, lifecycle/update evidence schemas,
product packages, the Live Control Lab, platform probes, and all Swift tests.
The final evidence commit is created only after an additional exact-current
rerun passes with this reconciled documentation present.

## Roadmap reconciliation

The current roadmap and architecture now state the implemented constraints:

- a Mac may retain up to eight paired iPhone/iPad clients;
- only one active remote session is admitted at a time;
- one display is streamed at a time, but Shared Display may switch inside the
  session through the normative acknowledged replacement exchange;
- candidate-stabilization physical checks may run before a soak, while final
  acceptance requires the exact frozen candidate's new seven-day campaign;
- the prior pre-physical goal and one-day campaign are historical, not active
  candidate evidence.

## Remaining gates

This audit does not freeze or accept a candidate. Remaining work is to:

1. construct, inspect, sign, and install one exact development candidate;
2. execute every safely automatable and explicitly authorized physical check,
   including multi-client administration and live display switching;
3. repair any candidate-blocking physical defect and repeat affected evidence;
4. freeze the stable source and start a new seven-day source-bound soak;
5. retain stable-Xcode, distribution, notarization, legal/privacy, private-route,
   external-cohort, and publication gates for Stage 3 rather than claiming them
   here.
