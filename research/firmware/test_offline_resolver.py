#!/usr/bin/env python3
"""Check modeled ARM64e fixups and fail-closed handling without Apple binaries."""

import struct
import unittest

from offline_resolver import arm64e_pointer, patch_chains


class FixupTests(unittest.TestCase):
    def test_authenticated_rebase_and_format_specific_offsets(self):
        self.assertEqual(
            arm64e_pointer((1 << 63) | (2 << 51) | 0x480, 12, 0x100000000),
            (16, 0x100000480, None, 0),
        )
        self.assertEqual(arm64e_pointer(0x100000480, 1, 0x100000000)[1], 0x100000480)
        self.assertEqual(arm64e_pointer(0x480, 9, 0x100000000)[1], 0x100000480)

    def test_bind_ordinals_and_signed_inline_addends(self):
        self.assertEqual(arm64e_pointer((1 << 63) | (1 << 62) | 0xABCDEF, 12, 0)[2:], (0xABCDEF, 0))
        raw = (1 << 62) | (0x7FFFD << 32) | 7
        self.assertEqual(arm64e_pointer(raw, 9, 0)[2:], (7, -3))
        with self.assertRaises(ValueError):
            arm64e_pointer(0, 13, 0)

    def test_rebase_only_changes_modeled_memory(self):
        # One segment, one page, one authenticated rebase. No imports.
        blob = struct.pack("<7I", 0, 28, 60, 60, 0, 1, 0)
        blob += struct.pack("<II", 1, 8)
        blob += struct.pack("<IHHQIHH", 24, 4096, 12, 0, 0, 1, 0)
        toc = {"loads": [{"load_cmd": "LC_DYLD_CHAINED_FIXUPS", "offset": 0, "size": len(blob)}]}
        memory = [{"address": 0x100000000, "data": bytearray(struct.pack("<Q", (1 << 63) | 0x120))}]
        stats = patch_chains(blob, toc, memory, 0x100000000, 0)
        self.assertEqual(struct.unpack("<Q", memory[0]["data"])[0], 0x100000120)
        self.assertEqual(stats, {"rebases": 1, "bindings": 0, "formats": [12]})
        broken = bytearray(blob)
        struct.pack_into("<H", broken, 28 + 8 + 6, 13)
        with self.assertRaises(ValueError):
            patch_chains(broken, toc, memory, 0x100000000, 0)


if __name__ == "__main__":
    unittest.main()
