# Compatibility and validation

## Runtime discovery validation in 1.3.4

On iPhone 13 (iPhone14,5), iOS 17.2.1 / 21C66 with roothide, all 18 code locations/fields and two live-object fields resolve uniquely. Native profile/details reads and test notifications pass. The test profiles match the immediate pretest baseline individually; the original test profile remains enabled. No download, enable/disable, deletion or reset was performed.

Linux image replay and a standalone iPhone program pass real-image, ASLR relocation, missing/ambiguous/interior-symbol, unreadable-image and cyclic/ambiguous-object-graph cases. Linux also passes ASan/UBSan. Unknown UUIDs and mismatched object sizes reject private-ABI approval.

Early process-wide Gum enumeration caused memory-highwater termination and was rolled back to 1.2.2. Subsequent fixes explicitly register Capstone ARM64, return initialization failures without exception unwinding and exclude shared_ptr control blocks from concrete-driver RTTI matching. The final design avoids global symbol caches and decodes incrementally to reduce temporary allocations.

This round did not repeat the complete write/switch flow. The previous 1.1.4 write results apply to the earlier transport. The resolver currently approves only the build above; these results do not establish other-iOS compatibility.

## Previous device research

Baseline: iPhone 13 (iPhone14,5), iOS 17.2.1 / 21C66, roothide, removable eSTK card in slot 2.

- 1.1.4 passed the complete test-profile download, rename, enable, disable, original-line restore and delete flow. The final test profiles matched individually.
- 1.1.7 passed card/notification reads, TLS, QR-image decoding and settings/notification UI checks. Camera preview checks passed.
- The original test profile was restored. Cellular data, SMS and calls were not tested.
- An earlier switch test encountered a management-channel issue after disabling a profile. Recovery and a fix followed; original profiles were not deleted.

## Validation for 1.2.x

Version 1.2.0 added English signaling logs, custom APDU/DER and bilingual UI. Version 1.2.1 added this offline manual and passed the device checks below. Version 1.2.2 updates the bundled records without changing the transport core.

- Native card/notification reads, TLS and QR-image decoding passed.
- All five articles opened and copied in both languages. Title/body/offset searches and the no-results state passed.
- English, Simplified Chinese and Follow system applied immediately. Dark-mode documents passed; logs remained English with Chinese UI.
- Raw APDU and ES10 DER Get EID returned identical results. A raw batch completed 61xx -> GET RESPONSE -> 9000.
- APDU/HTTP trace display, copy, matching export contents, share cancellation cleanup and clearing passed.
- Profiles matched the immediate pretest baseline individually. The enabled line and language preference were preserved. This round performed no download, enable/disable, deletion or reset.

Offline checks also cover language resources, manual/example/UUID/offset consistency, codecs, malformed inputs, CLA mapping, ASan/UBSan and real libeuicc mock-card flows for MSS 6/120/255, 256 blocks, 61xx and errors.

These results do not establish compatibility with every device, operator or custom command. Debug-driven interface checks are not acceptance tests of a physical camera scan.

## OpenEUICC feature comparison

Implemented interfaces include listing, downloading, enabling/disabling, renaming, deleting, card information, notification management and automatic-notification settings, default SM-DP+, optional download IMEI, proxy, MSS, switch refresh and confirmation-based entire-card reset.

- Proxy, IMEI, default-server changes, nondefault MSS/refresh and reset have not been fully tested on the current card. Reset has not been executed.
- Android OMAPI/system integration, MEP, multiple readers, USB CCID, forced TPDU, custom ISD-R AID and SM-DS automatic discovery are unsupported.
- There is no option to bypass TLS verification.
- Card policy can reject switching, deletion or reset. A feature's presence does not establish compatibility with every card.

The comparison used the official OpenEUICC repository at `https://gitea.angry.im/PeterCxy/OpenEUICC`, revision `2cbd7a1b3f2482003ace1583b64abf4015283e5a`.

## Remaining coverage

Other devices/firmware, all operators, installation interruption, card removal and prolonged background recovery have not been fully covered. UUID checks prevent applying existing offsets to unmatched firmware. Start the next device checks with read-only Get EID, inspect the trace and channel closure, then consider explicitly authorized writes.
