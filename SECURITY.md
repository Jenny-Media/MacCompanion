# Security Policy

Policy status: prepared for review; the private reporting route described below
is not operational until GitHub private vulnerability reporting is enabled and
verified for this repository.

## Supported versions

Mac Companion has no externally supported release yet. Source snapshots,
development builds, unsigned artifacts, and locally constructed evidence are
not production releases and receive no security-support promise.

Once an external beta exists, this section will list its supported release
channels and security-update window. Official support applies only to Jenny
Media-signed builds obtained through an official Jenny Media distribution
channel.

## Reporting a vulnerability

Do not report suspected vulnerabilities in a public issue, discussion, pull
request, or social-media post, and do not include credentials, pairing data,
diagnostics, screen content, or personal information in a public channel.

The intended initial route is GitHub private vulnerability reporting for
`Jenny-Media/MacCompanion`. After the repository setting is enabled and
verified, use the repository's **Security > Report a vulnerability** button:

<https://github.com/Jenny-Media/MacCompanion/security/advisories/new>

If that button is unavailable, private reporting is not operational. Do not
fall back to a public report. Jenny Media will publish an approved alternate
private contact before accepting external security reports if GitHub private
reporting cannot be made available.

Please include only the minimum information needed to reproduce and assess the
issue:

- affected version, commit, platform, and distribution channel;
- the security boundary and expected versus observed behavior;
- minimal reproduction steps and impact;
- whether credentials, private content, or other users may be affected; and
- a safe way to request any sensitive evidence separately.

Do not attach real secrets, signing material, provisioning profiles, pairing
keys, private databases, unredacted diagnostic exports, or screen recordings
containing private content.

## Coordinated handling

After intake is operational, Jenny Media will acknowledge a report, validate
scope, agree on a disclosure plan where practical, and publish remediation and
credit appropriate to the risk and reporter's wishes. Exact response targets
will be added before the first supported beta; no target is promised today.

Authorization to view source or submit a report is not authorization to access
another person's device or data, disrupt a service, evade Apple or platform
protections, or test production systems without written permission. Stop and
report privately if testing could expose private content or affect another
person.
