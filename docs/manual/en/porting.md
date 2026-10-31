# Porting and runtime discovery

## Runtime resolver in 1.3

The extension decodes ARM64 with Capstone 5 from the Frida Gum 17.25.0 devkit. Private symbols are enumerated with CoreSymbolication only in the driver module. Normal use needs no Frida server, JavaScript or computer. Substrate still installs the hooks.

Image analysis discovers 18 code locations/fields; read-only live-object inspection discovers two more fields. Candidates must be unique. Reports preserve evidence and failure state. There is no old numerical-offset fallback. Open Card management > Firmware resolver to refresh or copy the report; the report sends no APDU.

- Mach-O supplies loaded bases, code ranges, UUIDs and LC_FUNCTION_STARTS. Symbol candidates must be function starts inside the target image.
- Driver symbols and block instructions identify open/command/close, encoder, response and QMI callbacks and their captured fields.
- C++ RTTI, vtables and the virtual-method/worker/closure-constructor relationship locate SubscriberSimController, sender, worker and completion.
- Worker instructions identify the SimInfo vector, logical-slot field and state getter. The exported isSimReady predicate replaces a fixed state enum.
- Exported Registry getters supply the service map. A bounded linked-object search matches the unique controller vtable, removing the old map/node/typeinfo/vtable-slot offsets.
- Driver pointers require the exact concrete RTTI name, excluding shared_ptr control blocks whose type names also contain the driver name. Hardware-slot fields are checked across SimInfo nodes; logical and hardware slots remain distinct.

## Example discovery results

These are observations on iPhone14,5 / iOS 17.2.1, not configuration values or portable constants. Addresses are relative to their respective images. See tweak/ResolverCore.cpp, tweak/RuntimeResolver.mm and tweak/Apdu.mm.

| Item | Observed result |
|---|---|
| CommCenter UUID | 10bdb2fd04e33fcea0a188d064801df2 |
| Driver UUID | 571c9998ee7c3d9e946f779aee761332 |
| sender / worker | CommCenter +0x7e4568 / +0x7ff250 |
| Controller vtable / completion | CommCenter +0x175fb78 / +0x803a74 |
| SimInfo state getter | CommCenter +0x11c3c10 |
| SimInfo vector / logical slot | Controller +0xa8 / SimInfo +0x24 |
| Driver open / command / close | Driver +0x168858 / +0x1693e0 / +0x16a7a4 |
| Encoder / QMI / response | Driver +0x169bb8 / +0x16a214 / +0x16a43c |
| Encoder channel / response hardware slot / channel | Block +0x30 / +0x30 / +0x34 |
| QMI error field | Result +0x4 |
| Controller driver pointer / SimInfo hardware slot | Live object +0x68 / +0x20 |
| Ready predicate / Registry | Exported subscriber::isSimReady and Registry::getServiceMap |

## Supporting another build

1. Install the normal build and save its runtime report. Record device, baseband, architecture and UUIDs for diagnosis. Previously unseen UUIDs follow the same discovery path; no approval-table edit is needed.
2. Check compiledAbiCompatible, signaturesValidated, abiCompatible, codeResolved, hookStage and objectLayoutResolved. The adapter checks its own C++ layout and the complete driver parameter signatures. These checks infer compatibility; matching sizes/signatures do not formally prove every private ABI or slot semantic.
3. There is no UUID approval table. If discovery fails, use its reported evidence to update the affected semantic rule or adapter, then add image replay and negative cases. Do not substitute old numerical offsets or force a failed plan to complete.
4. Verify injection, arm64/arm64e, Substrate and rootless/roothide packaging. Start with live-object inspection, logical/hardware slot mapping, Get EID, listing, 61xx, channel close and disconnect recovery.
5. Then use an authorized, redownloadable profile to test download, enable, disable, restore and delete, comparing the original baseline individually. The default slot 2 does not identify physical slots on other devices.
6. Test wireless policy, GSMA TLS, camera/photos, foreground/background and restart separately. Standard LPA/UI code is usually reusable. Internal eUICC, MEP, other basebands and USB readers require separate transport work.

Discovery determines eligibility from available runtime evidence, not firmware identity. Missing symbols, stripped RTTI, changed signatures/instructions or ambiguous objects reject card operations with diagnostics. Live-object rules accept 1-16 SimInfo nodes and require a unique hardware-slot field with values 1-3; a single node may still leave several indistinguishable candidates. Different slot mappings need revised rules and device validation.

## Resource and validation limits

CommCenter has a small memory budget. Early process-wide Gum symbol enumeration caused memory-highwater termination, was rolled back and removed. The final design scopes CoreSymbolication to the driver and explicitly registers Capstone ARM64 and libc allocators without global Gum/GLib caches. maxMeasuredFootprintBytes is the maximum of a few stage samples, not a continuously measured process peak. Expected resolution failures return errors without C++ exception unwinding.

The new resolver still requires write/switch regression. This round's read-only checks cannot replace the 1.1.4 complete write test or establish other-firmware compatibility.
