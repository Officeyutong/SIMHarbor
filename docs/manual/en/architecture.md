# Technical architecture

The device-tested baseline is an iPhone 13 (iPhone14,5), iOS 17.2.1 / 21C66, roothide, with the removable eSTK eUICC in slot 2. Version 1.1.4 passed the native Test profile download/rename/enable/disable/restore/delete round trip. Version 1.1.7 passed the final device read-only checks. Version 1.2.1 passed device checks of documents/languages, logs and read-only custom signaling. Version 1.2.2 updates these bundled validation records without changing the transport core.

## Data flow

```text
UIKit interface / native libeuicc LPA
  + ES9+ -> NSURLSession HTTPS -> operator server
  + ES10 -> local HMAC IPC -> native CommCenter extension
                    -> subscriber / QMI driver
                    -> removable eUICC ISD-R
APDU and application-level HTTP exchanges -> English log
```

The app runs the LPA on the phone. The extension provides SIM-slot, logical-channel and APDU transport. Frida is a research/debugging tool, not a runtime requirement. Normal use does not require a computer to relay APDU or HTTP traffic.

Profile management and custom requests share a serial queue so that card reads, downloads and switching cannot concurrently own the management channel.

## Persistent card session

The high-level CommCenter sender accepts an **AID**, not an arbitrary raw APDU. The extension uses it to establish an ISD-R session and intercepts the driver's channel-close path to retain the session. It replaces generated APDU data for subsequent app requests, captures raw responses, then closes the channel and releases the original completion callback when finished.

When the SIM is inactive, the extension opens the management channel through the driver entry point. This allows management reads and line restoration after disabling a profile.

## App–extension communication

The app listens on `127.0.0.1:18099`. Bounded newline-delimited JSON carries requests and matching replies. A random challenge and role-separated HMAC authenticate both peers. The listener is not exposed remotely. This pairing does not isolate jailbreak root privileges; the app and extension are built with the same project pairing key.

The extension derives addresses and fields at runtime with driver-scoped CoreSymbolication, Frida devkit Capstone, RTTI and live-object checks. Both image UUIDs and the private ABI must be approved before hooks or card commands. The Firmware resolver screen exposes evidence; the Porting article explains the rules and remaining manual work.

## Network and logging

NSURLSession implements ES9+ HTTPS with system trust plus the bundled GSMA root and hostname verification. App-specific wireless access can be enabled without changing the trust store.

The log records app-visible APDU and application-level HTTP data. It does not capture encrypted TLS records or all internal modem signaling. The separate Logs and custom signals article describes retention, byte formats and command limits.
