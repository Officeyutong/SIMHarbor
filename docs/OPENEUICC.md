# OpenEUICC feature comparison

**English** | [简体中文](OPENEUICC.zh-CN.md)

This comparison uses the [official OpenEUICC source](https://gitea.angry.im/PeterCxy/OpenEUICC), checked out at `2cbd7a1b3f2482003ace1583b64abf4015283e5a` during research. References include `app-common/src/main/res/menu/profile_options.xml`, `fragment_euicc.xml`, `notification_options.xml`, `res/xml/pref_settings.xml` and the README. Android UI/system-integration code was not ported.

| Feature | SIMHarbor implementation and limits |
|---|---|
| Profile list, download and deletion | Native libeuicc; camera/photo QR import, manual activation and confirmation codes; deletion requires an inactive profile |
| Enable/disable | ES10c; close the channel and reread state after switching; UI confirmation |
| Rename | ES10c; up to 64 UTF-8 bytes; clearing restores the card's default name |
| Card information | EID, free storage/runtime memory, firmware/RSP/profile versions |
| Notifications | List, submit individually/in batches and remove after success, or remove only; separate automatic-notification settings for installation, deletion and switching |
| Default SM-DP+ | Read/write; SM-DS is read-only |
| Download IMEI | Optional 15-digit value used only for the current download |
| HTTP CONNECT proxy | Unauthenticated HTTP proxy setting; TLS/hostname checks remain enabled; an actual proxy service has not been tested |
| Switch refresh and APDU MSS | Refresh enabled by default; adjustable MSS 120/240/255 |
| Card reset | EID verification plus typed RESET confirmation; not tested on the user's existing card |
| Operation history | Exportable English workflow and raw APDU/HTTP signaling; may contain activation credentials (1.2.0) |
| Android OMAPI/privileged integration, MEP and multiple readers | Not ported; the original comparison covered the validated iOS firmware and physical slot 2 |
| USB CCID and forced TPDU | USB readers are unsupported by the current CommCenter transport |
| Custom ISD-R AID | The extension accepts only the standard ISD-R AID |
| Developer TLS bypass | Not offered; system trust and GSMA roots are used |
| Automatic SM-DS discovery/operator system-settings integration | Not implemented; downloads require activation codes |

“Implemented” means the interfaces and UI are connected. [Validation scope](VALIDATION.md) records device testing separately; implementation does not establish coverage of every operator or setting.

Version 1.2.0 added the bilingual UI and raw APDU/DER console, initially checked through local builds and offline tests. See [architecture and porting](ARCHITECTURE_PORTING.md).
