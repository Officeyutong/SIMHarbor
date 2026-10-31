# Logs and custom signals

## English raw traces

Logs uses UTC timestamps and records app stages, APDU TX/RX, SW, HTTP method/URL/application-level request and response headers, status codes, body chunks in hexadecimal and transport errors.

- `TX` is an attempt to send; `RX` is a received response. A timeout does not prove that the card did not execute the command.
- `HEX` contains the actual bytes. Reassemble bodies by message ID and `offset`; `length` gives the total byte count.
- `SW=9000` is an APDU success status. The response body must still be parsed to determine the ES10 operation result.
- This is app-visible application signaling, not a capture of all phone traffic, encrypted TLS records or internal baseband QMI messages.
- The in-memory trace retains approximately 4 MiB, then evicts older records and reports their count. Export creates a `.log` file.
- Raw HTTP/APDU data may contain activation credentials, certificates, encrypted profile packages and card identifiers.

## Raw APDU mode

Enter one short APDU per line, up to 64 commands. Use hexadecimal and whitespace; lines beginning with `#` are comments. Length must be 4–261 bytes with consistent Lc and optional Le. Extended-length APDUs are unsupported.

Use a basic-channel CLA such as `00` or `80`. The app binds the allocated logical channel and supports CLA encoding for channels 0–19.

Responses remain raw. There is no automatic `61xx` or `6Cxx` handling. The default stops a batch on a status other than `9000`; turn it off to arrange GET RESPONSE or other commands yourself. Commands are never retried automatically.

Read-only Get EID example; the example button fills text without sending:

```text
80 E2 91 00 06 BF 3E 03 5C 01 5A
```

## ES10 DER mode

Enter one complete DER TLV. The existing libeuicc sends STORE DATA blocks and collects subsequent `61xx` responses. The console shows the concatenated response body; Logs contains every APDU and SW.

- Uses the configured MSS, default 120.
- Limits: 256 request blocks, 4096 exchanges and 1 MiB of responses.
- This mode currently permits channels 0–3 because of the library's channel encoding.
- Arbitrary HTTP requests are not provided.

The DER for the same Get EID request:

```text
BF 3E 03 5C 01 5A
```

## Send and finish

Review the bytes, tap Send and confirm. Requests share the serial operation queue and close the channel afterward. Responses received before an error remain available. Custom commands can modify or erase profiles; reading an article never executes them.

Both read-only Get EID modes passed on the device in 1.2.1. Raw mode returned 6115, then completed with 9000 when the request and GET RESPONSE were sent in one batch with stop-on-status disabled. DER mode automatically collected the identical EID body. No card-modifying custom commands were tested.
