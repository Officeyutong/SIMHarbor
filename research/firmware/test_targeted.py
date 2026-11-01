#!/usr/bin/env python3
"""Validate conservative classification, explicit download scope and parser bounds."""

import copy
from pathlib import Path
import tempfile
import unittest

from change_points import classify
from download import validate
from extract import select_identity
from macho_inspection import function_starts


class TargetedTests(unittest.TestCase):
    def test_customer_identity_is_board_specific_and_excludes_recovery(self):
        def identity(board, variant):
            return {"Info": {"DeviceClass": board, "Variant": variant}}

        customer = identity("D93AP", "Customer Erase Install (IPSW)")
        recovery = identity("D93AP", "Recovery Customer Install")
        other_board = identity("D94AP", "Customer Erase Install (IPSW)")
        manifest = {"BuildIdentities": [recovery, customer, other_board]}
        self.assertIs(select_identity(manifest, {"d93ap"}), customer)
        with self.assertRaises(ValueError):
            select_identity(manifest, set())
        with self.assertRaises(ValueError):
            select_identity({"BuildIdentities": [recovery]}, {"d93ap"})

    def test_strings_and_uuid_do_not_establish_a_code_change(self):
        value = classify('CStrings:\n+ "new APDU log"\n- UUID: OLD\n+ UUID: NEW\n')
        self.assertEqual(value["classification"], "no_code_change_evidence_in_summary")
        value = classify("-  __TEXT.__text: 0x100\n+  __TEXT.__text: 0x104\n")
        self.assertEqual(value["classification"], "reported_code_change")
        self.assertEqual(value["text_size"], {"old": 256, "new": 260})

    def test_block_number_churn_is_not_function_body_evidence(self):
        value = classify(
            "Symbols:\n- __ZNsendSimApdu_command_block_invoke.7\n+ __ZNsendSimApdu_command_block_invoke.9\n"
        )
        self.assertTrue(value["apdu_symbol_changes_only_renumbered"])
        self.assertEqual(value["classification"], "no_code_change_evidence_in_summary")
        value = classify("Functions:\n~ __ZNisSimReady : 64 -> 88\n")
        self.assertEqual(value["classification"], "reported_code_change")
        self.assertEqual(len(value["relevant_function_size_changes"]), 1)

    def test_downloads_require_explicit_unique_assets_and_budget(self):
        asset = {
            "asset": "a" * 24,
            "sha256": "b" * 64,
            "url": "https://updates.cdn-apple.com/fixture.ipsw",
            "size": 100,
        }
        self.assertEqual(validate({"assets": [asset]}, 100)[1], 100)
        with self.assertRaises(ValueError):
            validate({"assets": [asset]}, 99)
        with self.assertRaises(ValueError):
            validate({"assets": [asset, asset]}, 200)
        for url in (
            "https://updates.cdn-apple.com.example.invalid/file",
            "http://updates.cdn-apple.com/file",
            "https://user@updates.cdn-apple.com/file",
        ):
            candidate = copy.deepcopy(asset)
            candidate["url"] = url
            with self.assertRaises(ValueError):
                validate({"assets": [candidate]}, 100)

    def test_function_start_bounds_and_malformed_uleb(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture"
            toc = {
                "loads": [
                    {"load_cmd": "LC_SEGMENT_64", "name": "__TEXT", "addr": 4096, "memsz": 512},
                    {"load_cmd": "LC_FUNCTION_STARTS", "offset": 0, "size": 3},
                ]
            }
            path.write_bytes(b"\x04\x08\x00")
            self.assertEqual(function_starts(path, toc), [4100, 4108])
            for raw in (b"\x80\x80\x80", b"\xff" * 12, b"\xff\x7f\x00"):
                path.write_bytes(raw)
                toc["loads"][1]["size"] = len(raw)
                with self.assertRaises(ValueError):
                    function_starts(path, toc)
            toc["loads"][1]["size"] = 100
            with self.assertRaises(ValueError):
                function_starts(path, toc)


if __name__ == "__main__":
    unittest.main()
