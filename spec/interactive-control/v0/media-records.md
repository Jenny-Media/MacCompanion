# Interactive Control media records v1

Status: normative binary framing. Channel authentication, credential construction, and session-control messages remain separate prerequisites.

Each media record is one 96-byte header followed by exactly `payloadLength` bytes. Integers are unsigned big-endian. UUIDs are the 16 RFC 4122 bytes in network order. A receiver reads and validates the fixed header before allocating payload storage. Any mismatch closes the media channel.

| Offset | Bytes | Field | Rule |
| ---: | ---: | --- | --- |
| 0 | 4 | magic | ASCII `MCM1` |
| 4 | 1 | version | `1` |
| 5 | 1 | record type | `1` configuration, `2` video access unit, `3` discontinuity, `4` end |
| 6 | 2 | flags | Bit 0 is `cleanKeyframe`; all other bits are zero |
| 8 | 2 | header length | `96` |
| 10 | 2 | reserved | zero |
| 12 | 4 | payload length | Record-specific bound below |
| 16 | 16 | Interactive Control session ID | Exact current session UUID |
| 32 | 8 | authorization epoch | At least 1 and current |
| 40 | 16 | surface ID | Exact current session-scoped surface UUID |
| 56 | 8 | surface revision | At least 1 and current |
| 64 | 8 | coordinate-space revision | At least 1 and current |
| 72 | 8 | media sequence | At least 1; strictly increases per media channel |
| 80 | 8 | presentation time | Nanoseconds in the channel's monotonic media timeline |
| 88 | 2 | encoded width | Record-specific bound below |
| 90 | 2 | encoded height | Record-specific bound below |
| 92 | 4 | reserved | zero |

Configuration records contain 1–4,096 bytes of AVCC decoder configuration, have zero flags, and carry nonzero dimensions. Video access units contain 1–8,388,608 bytes of AVCC data; bit 0 is set exactly for a clean random-access keyframe. For both, width is 1–1,920, height is 1–1,200, and their product is at most 2,304,000 pixels.

The v1 AVCC profile uses a four-byte big-endian NAL-unit length (`lengthSizeMinusOne == 3`). Decoder configuration requires version 1, exact reserved bits, 1–8 nonempty SPS records of NAL type 7, 1–8 nonempty PPS records of type 8, and no trailing bytes except the completely parsed profile-extension form, whose optional SPS extensions are type 13. Each access-unit NAL has a positive in-bounds four-byte length, a clear forbidden bit, and type 1–23. An access unit contains at least one video slice (type 1–5), and `cleanKeyframe` is set if and only if it contains an IDR slice (type 5). Annex-B start codes, truncation, false keyframe claims, and configuration-only access units are rejected before the runtime queue.

Discontinuity and end records have zero payload, flags, width, and height. They still carry the exact session, epoch, surface, revisions, sequence, and timeline value so an old record cannot terminate or reset a replacement stream.

The client rejects duplicates, non-increasing sequence, a stale epoch/surface/revision, an impossible keyframe flag, and a configuration change not followed by a clean keyframe. Payload parsing happens only after header validation and bounded allocation. Relays do not decode or persist payloads.

`spec/fixtures/valid/interactive-media-header.json` contains the authoritative 96 binary bytes as lowercase hexadecimal plus decoded expectations. Invalid vectors mutate those exact bytes. JSON is only the fixture container; it is not the media transport.
