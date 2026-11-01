# Shared JSON models

**English** | [简体中文](JSON_MODELS.zh-CN.md)

SIMHarbor 1.3.20 uses the vendored, unmodified **nlohmann/json 3.12.0** single header for all project-owned runtime JSON parsing and serialization. libeuicc retains its upstream C/cJSON implementation; the Python build/test tools continue to use Python's standard JSON module.

## Files and responsibilities

| File | Responsibility |
|---|---|
| [Protocol.hpp](../shared/Protocol.hpp) | Shared operation/phase enums, handshake, request, reply, slot, resolver, HTTP status and article models. |
| [JSON.hpp](../shared/JSON.hpp) | Bounded parsing and checked conversion of fields, integers, arrays, maps and optional values. |
| [Framing.hpp](../shared/Framing.hpp) | LF-delimited socket reads/writes and decoding directly into protocol structures. |
| [JSONFoundation.h](../shared/JSONFoundation.h) | Conversion between Foundation UI/diagnostic values and the nlohmann DOM. No second JSON parser is involved. |
| [Bridge.mm](../viewer/Bridge.mm) / [Apdu.mm](../tweak/Apdu.mm) | Typed IPC client/server API and dispatch. |

Project files that need C++ models compile as Objective-C++. Public C helpers keep C linkage; libeuicc remains compiled as C. UIKit's card/profile dictionaries and NSError snapshots remain Foundation models, not wire decoders. Slot lists remain typed through the app's selection logic.

## Typed protocol flow

A request is a `Request` containing a validated `Operation`, correlation ID and operation fields. Factories such as `Request::open`, `Request::transmit` and `Request::status` make callers explicit. The bridge assigns a fresh ID before sending.

A `Reply` holds the ID/success/error envelope and a `std::variant` of operation-specific bodies: `ResolverReply`, `SlotsReply`, `StatusReply`, `OpenReply` or `TransmitReply`; close has an empty body. The expected request operation selects the reply schema. The bridge also checks the correlation ID before exposing a reply to the caller. Business code reads structure members rather than string-key dictionaries.

`Phase` is shared by the app and tweak. It is serialized as the existing integers 0–4. `Operation` keeps its existing string values. Resolver reports retain their flattened wire layout, including the shorter initializing report. Resolver locations use a string/unsigned-integer variant because address strings and live-member numeric offsets have different existing representations.

The models use `NLOHMANN_JSON_SERIALIZE_ENUM` and `NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE` where suitable. Deserialization uses explicit checked `read` functions. These validate types and ranges before accessing values, so expected malformed input does not require C++ exception unwinding inside CommCenter. Missing required fields are errors; explicitly optional fields may be absent or null. Unknown fields are ignored for forward-compatible additions.

## Input validation and framing

- Require the expected object/array shape and exact string/boolean types. Booleans and floats cannot masquerade as integer slots; values must fit the target integer type.
- Validate operations, phase range, positive logical slots, hardware slots, channel numbers, hexadecimal fields and slot-list uniqueness. Unknown operations are rejected rather than mapped to a valid default operation.
- Reject invalid JSON/UTF-8, duplicate object keys and nesting deeper than 64, including inside unknown fields. JSON object key order is irrelevant.
- Cap socket frames at **262,144 bytes including LF**, so both sender and receiver permit at most **262,143 JSON bytes**. This resolves the previous one-byte sender/receiver limit mismatch.
- Malformed handshake/request/reply schemas terminate the affected connection. An invalid or mismatched reply ID also disconnects the peer. Requests are not automatically replayed.

The wire field names, handshake HMAC construction, request IDs, port and APDU transport semantics remain unchanged. See [IPC](IPC.md) for the full protocol. Paired app/extension builds remain required.

## Other JSON boundaries

The bundled guide decodes into `std::vector<Article>`. Project-owned inspection of operator HTTP status decodes into `HTTPEnvelope` / `HTTPHeader` / `ExecutionStatus` / `StatusCodeData`; libeuicc's actual RSP request/response processing is unchanged. Error details, trace output and CLI snapshots serialize via nlohmann, using the Foundation conversion adapter for existing UI/diagnostic models. That adapter preserves boolean/signed/unsigned number types, Unicode and embedded NULs, and rejects unsupported values or non-finite numbers.

## Dependency and checks

Source URLs, version and SHA256 hashes are recorded in [vendor/nlohmann/PROVENANCE.json](../vendor/nlohmann/PROVENANCE.json). Its MIT license is included in the source and the app's open-source notices; it does not change libeuicc's license.

`tests/test_json.cpp`, run by `python3 tests/check_offline.py`, covers schema round trips, invalid types/ranges, duplicate/deep inputs, existing wire fields, fragmented frames, truncated input and size boundaries under ASan/UBSan. The installed executable's `--json-check` exercises Foundation conversions and typed replies without card or network operations. Existing error and notification fixture modes remain available. Device checks are still required to validate the actual CommCenter/driver path.
