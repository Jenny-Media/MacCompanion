# Semantic DER-entitlement equality

Date: 2026-08-22

## Claim

The per-architecture embedded-signature inspector now independently decodes a
modern CoreEntitlements v1 DER sibling and admits it only when its exact tagged
value equals the duplicate-safe XML entitlement projection and the pinned
signing policy. This closes the DER-semantic prerequisite without changing any
outer-bundle, notarization, packaging, stable-toolchain, physical, or promotion
claim. Every architecture result remains `platformAcceptanceEligible: false`.

The decoder accepts only the measured closed grammar: application tag `0x70`,
minimal integer version `1`, dictionary tag `0xb0`, sequence dictionary entries
and arrays, UTF-8 strings, canonical one-byte Booleans, and minimal signed
integers. It requires definite minimal lengths, complete root and entry
consumption, uniquely sorted ASCII dictionary keys, NFC non-control text, safe
integers, and the existing signing-policy depth, child, key, node, and aggregate
string budgets. Unknown tags, nonminimal lengths or integers, malformed UTF-8,
duplicate or reordered keys, unsupported values, trailing bytes, and XML/DER
semantic disagreement fail closed.

DER-only entitlement signatures remain outside v0.1. A normal XML-plus-DER
signature retains SHA-256 for both complete embedded blobs; neither sibling is
treated as authoritative by omission.

## Apple-format evidence

Apple's open-source signer passes the parsed XML entitlement dictionary to
`CESerializeCFDictionary` and embeds the result in CodeDirectory slot 7. Apple's
open-source static verifier constructs its entitlement dictionary from that DER
slot when present. The public source locations are:

- [Security signer](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/signer.cpp)
- [Security static verifier](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/StaticCode.cpp)
- [CodeDirectory slot definitions](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/codedirectory.h)
- [XNU embedded-blob constants](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h)

A disposable unsigned Mach-O was ad-hoc signed with the fixed system
`/usr/bin/codesign --generate-entitlement-der` command and a neutral dictionary
covering an array, string, negative integer, false and true Booleans, nested
dictionary, multibyte positive integer, and zero. The exact 85-byte DER payload
is frozen in `scripts/validate_platform_code_signature.py`; the independent
fixture encoder must reproduce it byte for byte before the production decoder
is exercised.

A separate read-only compatibility probe extracted XML and DER siblings from
both architectures of an installed notarized third-party Developer ID app. The
production decoders produced exact equality for both the `x86_64` 1,292-byte
XML/824-byte DER pair and the `arm64` pair. The app was not launched, modified,
or resigned, and no third-party entitlement bytes or identities are retained in
the repository.

## Adversarial validation

`scripts/validate_platform_code_signature.py` now proves:

- byte-for-byte reproduction and semantic decoding of the Apple-tool vector;
- a complete XML-plus-DER embedded signature matches policy and retains both
  blob digests;
- different XML and DER Boolean values fail semantic equality;
- DER-only signatures remain rejected;
- wrong envelopes, trailing bytes, unsupported versions, missing root
  dictionaries, nonminimal lengths and integers, noncanonical Booleans,
  malformed UTF-8, unsupported value tags, duplicate keys, and reordered keys
  fail closed; and
- the existing embedded-signature, graph, Apple-display, certificate, runtime,
  timestamp, and policy correlations continue to pass.

The focused embedded, display-parser, and protected-executor validators pass,
including Python bytecode compilation. Repository-wide validation is recorded
with the commit that publishes this checkpoint.

## Remaining boundary

The next release-evidence gate is exact outer-bundle verification plus
notarization, stapling, Gatekeeper, packaging-equivalence, and canonical-record
correlation. Only that completed record may change platform acceptance for a
real final candidate. The exported iOS artifact, stable Xcode 26.6 reproduction,
credential custody, physical-device matrices, explicit Agent enablement, and
human promotion remain independent requirements.
