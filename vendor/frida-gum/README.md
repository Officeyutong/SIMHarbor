# Embedded Frida Gum / Capstone

**English** | [简体中文](README.zh-CN.md)

Unmodified official Frida Gum devkits **17.25.0**, iOS arm64 and versioned arm64e. Provenance URLs and original archive/library SHA-256 values are in PROVENANCE.json. Both architecture-specific headers and static libraries are included for reproducible relinking.

Only the bundled Capstone 5 ARM64 decoder is referenced from the static archive. Explicit architecture registration and libc allocator setup avoid Gum/GLib initialization. Module-scoped private-symbol lookup uses the platform CoreSymbolication API directly; process-wide Gum enumeration exceeded CommCenter's memory budget in an early device test. The tweak does not include GumJS, a JavaScript runtime or a Frida-server requirement. Hook installation remains through the existing Substrate interface. Link flags restrict symbol exports so embedded Gum/GLib/Capstone symbols do not interpose on separately attached Frida agents.

Source: https://github.com/frida/frida-gum/tree/17.25.0 . Upstream build/dependency instructions: https://github.com/frida/frida . `COPYING` preserves the upstream wxWindows licence and bundled notices; `COPYING.LIB` is the existing LGPL-2.1 licence text. No upstream library modifications were made. For a source rebuild, use the exact release's Frida build environment and iOS SDK, then regenerate the ios-arm64 and ios-arm64e gum devkits and verify their ABI before replacing these inputs.
