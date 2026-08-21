# Restricted canonical JSON profile v0.1

Status: normative and executable for capability parameters. This profile is a strict subset of [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785.html) and I-JSON.

## Accepted values

- `null`, `true`, and `false`;
- Unicode strings with no lone surrogate and no normalization;
- integers in `-9007199254740991...9007199254740991`;
- arrays of at most 128 accepted values;
- objects of at most 64 exact, non-duplicate Unicode property names and accepted values;
- at most 12 container levels, at most 4,096 UTF-8 bytes per string, and at most 65,536 input bytes.

Floating-point syntax, exponent syntax, NaN, infinity, unsafe integers, duplicate exact property names, invalid UTF-8/Unicode, and larger/deeper values are rejected. Supporting non-integer IEEE 754 values requires a later negotiated profile with complete ECMAScript number-serialization vectors; Foundation formatting is not assumed conformant.

## Canonicalization

The encoder emits no whitespace. Literals and safe integers use their shortest fixed spelling; negative zero becomes `0`. Strings use the RFC 8785 escapes: lowercase `\\u00xx` for control characters without a short escape, the five short control escapes where defined, escapes only quote and backslash outside controls, and otherwise preserves Unicode scalars exactly. It never normalizes text and never escapes `/`.

Object members sort recursively by the unsigned UTF-16 code units of the unescaped property names. Swift `String` dictionary/set equality is not an authority because it treats some canonically equivalent spellings as equal. The executable model retains ordered members and detects duplicates using exact Unicode scalar sequences.

## Capability schema slice

The executable v1 schema is closed and programmatic. It supports booleans, bounded safe integers, bounded strings with an optional closed enum, bounded arrays, and closed objects with at most 32 ASCII identifier properties and explicit required flags. Unknown properties, type mismatches, normalization-equivalent enum substitutions, missing required members, and constraint failures are denied before hashing.

`spec/fixtures/canonical-json-v0.1.json` is authoritative for RFC property sorting, recursive sorting, string escaping, literals, integer boundaries, duplicate denial, floating-point denial, unsafe-integer denial, and lone-surrogate denial. `spec/fixtures/crypto/operation-v0.1.json` proves that the canonical parameter bytes feed the exact durable operation binding.
