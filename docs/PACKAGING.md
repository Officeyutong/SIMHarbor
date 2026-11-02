# Package variants

**English** | [简体中文](PACKAGING.zh-CN.md)

SIMHarbor uses the same pinned [roothide/Theos](https://github.com/roothide/theos) to build all three variants, following the [roothide Developer README](https://github.com/roothide/Developer). Source files currently do not open jailbreak-resource paths directly. System framework paths stay unchanged. If jailbreak-file access is added, use the documented `jbroot()` API instead of hardcoding a jailbreak root.

| `SIMHARBOR_SCHEME` | Theos scheme | Debian architecture | App install path |
| --- | --- | --- | --- |
| `rootful` | empty | `iphoneos-arm` | `/Applications/ESTKLog.app` |
| `rootless` | `rootless` | `iphoneos-arm64` | `/var/jb/Applications/ESTKLog.app` |
| `roothide` (default) | `roothide` | `iphoneos-arm64e` | `/Applications/ESTKLog.app` in the roothide environment |

The extension is installed under the corresponding prefix's `Library/MobileSubstrate/DynamicLibraries`. Theos selects the dependency library paths and install names for each scheme. The app is arm64; the extension contains arm64 and versioned arm64e slices. Package architecture labels describe jailbreak packaging, not the executable slices.

The app includes all four entitlements required by the Developer README: `platform-application`, `com.apple.private.security.no-sandbox`, `com.apple.private.security.storage.AppBundles`, and `com.apple.private.security.storage.AppDataContainers`. The post-install script is generated with the correct app prefix, refreshes the app registration and restarts CommCenter, briefly interrupting cellular service.

## Local builds

After setting up the dependencies described in the README, run:

```sh
for scheme in rootful rootless roothide; do
    SIMHARBOR_SCHEME="$scheme" bash build.sh
    python3 ci/collect_artifacts.py --scheme "$scheme"
done
```

Each invocation cleans the build before changing schemes. Verification checks real deb metadata, app/tweak install paths, post-install registration paths, bundled user guides and Mach-O slices, including the versioned arm64e ABI. Named packages, per-scheme checksums and build metadata are collected in ignored `dist/`. Install both binaries from one package; different builds generate different pairing keys.

## CI and compatibility

Every push runs three independent build jobs and uploads one artifact per scheme, including diagnostics on failure. Releases remain limited to version changes on the default branch, require all three jobs to succeed, and publish all three debs together with verified checksums. Each package uses the same runtime capability checks; there is no firmware UUID allowlist. The available phone tests only roothide; rootful/rootless package validation alone does not establish device compatibility on those jailbreaks.
