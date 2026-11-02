# Validation scope

**English** | [简体中文](VALIDATION.zh-CN.md)

## Existing device validation

The current ABI checks cover iPhone 13 / iOS 17.2.1 (21C66), roothide and a removable eSTK eUICC.

- Historical native LPA tests completed authorized profile download, rename, enable, disable, restore and deletion.
- Later runtime resolver tests checked code locations, object fields and read-only card operations. Full write/switch regression has not been repeated for that resolver version.
- Synthetic QR images and metadata/image-picker callback handoff passed, including retaining results while busy, cancellation and duplicate frames.
- Physical-camera continuous focus, tap-to-focus/exposure coordinates and scene restoration properties passed checks. QR readability across distances and lighting still needs manual verification.
- The bilingual About page passed UI checks for version/build, public developer links, documentation and licenses.

These results do not establish compatibility for other devices, firmware, operators, long background recovery or interrupted installations. Real activation information and personal card baselines are excluded from this document.

## Public repository checks

`python3 tests/check_offline.py` checks language resources, documentation, privacy, C codecs and libeuicc mock-card flows. `python3 tests/test_ci_policy.py` checks release conditions. `python3 scripts/check_public_tree.py` audits the Git file set.

GitHub CI runs offline checks and builds without connecting to research devices. Each build regenerates nonpersistent pairing material. Repository manifests record dependency sources and pinned versions.

## Adaptive resolver validation in 1.3.22

- Six authorized firmware samples (16.5.1, 17.2.1, 17.6, 18.0, 18.6 and 26.0.1) passed static resolver replay under ASan/UBSan. No target ARM64 instructions execute.
- Synthetic traversal tests cover inline/indirect storage, changed stride/pointee displacement, out-of-bounds fields, overwritten registers and missing bounds branches, slot matches, backedges or readiness calls. Typed views cover container changes and failed reads. Actual-image negative cases reject missing signatures, incompatible signatures and callback addresses inside a function.
- The new roothide package was installed on iPhone 13 / iOS 17.2.1. Discovery, ABI, hooks and live-object checks passed. Two slots were enumerated, the eUICC EID/profile list was read and the ordinary SIM returned the expected ISD-R error.
- The native-continuation path on 18.x/26 has no corresponding device validation and currently requires a ready SIM; inactive-card access on that path is unsupported. This validation does not test download, deletion, line switching or real operator notifications.

These results do not establish compatibility for every iOS 14–26.0.1 device/build. Runtime evidence still determines eligibility without an OS/device allowlist.
