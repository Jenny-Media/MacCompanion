# Mac Companion diagnostic CLI profile v0.1

Status: normative for the bundle-independent `maccompanionctl` command model.
The permanent executable, code-signing identity, audit-token extraction,
designated-requirement validation, and XPC transport remain gated release
artifacts.

## Authority boundary

The CLI is never authorized by its path, executable name, current user, command
arguments, or a caller-supplied role. A final macOS adapter authenticates the
peer and assigns `diagnosticCLI`; only then may the Agent apply the closed local
IPC method matrix. This profile cannot open Agent persistence, contact a remote
Mac Companion client, invoke providers, or start Observe, Act, or Control.

The v0.1 matrix permits exactly:

- `negotiateProtocol` followed by `readAgentStatus`; or
- `negotiateProtocol` followed by `exportDiagnostics`.

Help and version output are local and perform no IPC. Every other responsibility
listed as a future CLI idea in the product architecture remains unavailable
until the local-IPC specification adds a separately reviewed method and policy.

## Invocation grammar

The parser receives arguments after the executable name and accepts only these
complete forms:

```text
status
status --json
diagnostics export
diagnostics export --json
help | --help | -h
version | --version
```

There are no global options, abbreviations, combined short flags, implicit
commands, environment-variable options, configuration files, endpoint
arguments, output paths, or pass-through provider arguments. Duplicate options,
missing subcommands, unknown commands, and extra arguments fail before IPC.
Parse failures do not reflect the rejected argument into output.

## Output

Successful output is UTF-8 and ends with one line feed. `--json` emits the exact
validated `LocalAgentStatusSnapshot` or `LocalDiagnosticExport` as compact JSON
with lexicographically sorted object keys. Text output uses only fixed English
labels, closed enum raw values, bounded counts, protocol numbers, diagnostic
sequence numbers, and Unix-millisecond timestamps.

Text and JSON output never add host names, user names, device names or IDs,
addresses, endpoint text, DNS names, paths, window or application titles,
provider identifiers, capability parameters, operation results, session IDs,
input content, arbitrary diagnostic messages, database errors, or signing
details. Empty closed lists render as `none`. Export events retain only their
bounded sequence, timestamp, component, severity, code, and occurrence count.
The renderer revalidates the complete typed value before producing any bytes.

`diagnostics export` writes to standard output only. File creation, overwrite,
atomicity, permissions, and destination policy are outside v0.1; callers may
redirect output using their shell at their own authority boundary.

## Exit status and errors

The final executable must use these stable process statuses and fixed stderr
messages. It must not append a provider, framework, XPC, filesystem, signing,
or decoded peer error.

| Status | Category | Fixed message |
| ---: | --- | --- |
| 0 | success | none |
| 2 | usage | `Invalid maccompanionctl command.` |
| 3 | peer authentication | `Mac Companion rejected the CLI signing identity.` |
| 4 | protocol incompatible | `Mac Companion local protocol is incompatible.` |
| 5 | service unavailable | `Mac Companion Agent is unavailable.` |
| 6 | request denied | `Mac Companion denied the diagnostic request.` |
| 7 | invalid response | `Mac Companion returned an invalid diagnostic response.` |
| 8 | output failure | `maccompanionctl could not write its output.` |
| 9 | internal failure | `maccompanionctl failed.` |

Usage failures may additionally print the fixed help text. A broken output sink
maps to status 8 without retrying an Agent request. Transport ambiguity cannot
be represented as success.

## Authoritative corpus

`spec/fixtures/cli-v0.1.json`, indexed only by
`spec/fixtures/manifest.json`, owns valid and invalid argument cases, exact
request plans, fixed text output, and failure mappings. The existing local
diagnostic export fixture supplies the typed rendering input. Package tests must
consume these files rather than creating another CLI corpus.
