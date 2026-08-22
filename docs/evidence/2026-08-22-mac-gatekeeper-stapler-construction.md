# Mac Gatekeeper and stapler construction

Date: 2026-08-22

Status: app-level non-acceptance construction evidence on macOS 27 and Xcode 27
beta.

## Measured Apple-tool contract

A read-only compatibility probe used the installed notarized Tailscale app as
an output oracle. No installed app, signature, ticket, or policy was modified.
The fixed runner measured:

```text
/usr/sbin/spctl --assess --type execute --verbose=4 SUBJECT
```

with empty stdout and exactly:

```text
SUBJECT: accepted
source=Notarized Developer ID
```

on stderr. The directly resolved Xcode binary used:

```text
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler validate SUBJECT
```

with empty stderr and exactly:

```text
Processing: SUBJECT
The validate action worked!
```

on stdout. Stapler validation may contact Apple's ticket service; the probe
was read-only with respect to the assessed application.

## Construction

`platform_signing_subjects.py` now derives one Mac-application assessment plan
from the same exact graph/reconstructed subject selected for the outer signing
check. It pins `/usr/sbin/spctl` and permits only the exact stable or beta Xcode
`stapler` binary path recorded by the fixed-tool identity.

`platform_mac_assessment.py`:

- freshly revalidates the complete correlated whole-object, architecture, and
  outer signing evidence before assessment;
- rederives the exact assessment plan;
- rehashes the complete reconstructed subject before and after each tool;
- parses only the measured path-bound success grammars;
- does not invoke stapler after Gatekeeper failure;
- repeats the complete signing-prerequisite reinspection after assessment; and
- retains `notarizationCorrelation: null` and
  `platformAcceptanceEligible: false`.

## Verification

```text
python3 scripts/validate_platform_mac_assessment.py
```

The focused validator proves the exact fixed argv, injected success grammar,
failed-Gatekeeper short circuit, warning rejection, outer-prerequisite
substitution rejection, assessment-plan substitution rejection, and subject
mutation detection. It is included in `scripts/validate.sh`.

## Remaining boundary

The synthetic reconstructed fixture is unsigned and no positive result from it
is represented. The installed-app probe is not Mac Companion evidence. The
checkpoint does not submit anything to Apple's notary service, correlate an
Accepted submission to an exact upload hash, staple or assess a final Mac
Companion app or DMG, validate packaging equivalence, use stable Xcode 26.6, or
clear any release, physical, or promotion gate.
