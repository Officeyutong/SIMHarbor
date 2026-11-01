#!/usr/bin/env python3
"""Check scope boundaries and metadata/report coverage semantics without a network."""

import contextlib
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import analyze
import catalog
import precomputed


class ScopeTests(unittest.TestCase):
    def test_inputs_ignore_body_examples_and_keep_device_build_pairs(self):
        text = """## IPSWs
`iPhone14,5_17.2_21C62_Restore.ipsw`
`iPhone15,2_17.2.1_21C66_Restore.ipsw`
## MachO
"iPhone16,1_17.3_21D50_Restore.ipsw"
"""
        inputs = precomputed.firmware_inputs(text)
        self.assertEqual(
            [(i["build"], i["devices"]) for i in inputs],
            [("21C62", ["iPhone14,5"]), ("21C66", ["iPhone15,2"])],
        )
        self.assertFalse(precomputed.firmware_inputs('"iPhone14,5_17.2_21C62_Restore.ipsw"'))

    def test_tree_discovery_recovers_broken_homepage_links(self):
        commit, ios = "a" * 40, "b" * 40
        trees = {
            commit: [{"path": "iOS", "type": "tree", "sha": ios}],
            ios: [
                {"path": "18_5_22F5053f__vs_18_5_22F5053j", "type": "tree", "sha": "c" * 40},
                {"path": "26_0_23A345__vs_26_0_2_23A999", "type": "tree", "sha": "d" * 40},
            ],
        }
        link = {
            "path": "iOS/18_5_wrong__vs_18_5_wrong/README.md",
            "label": "wrong",
            "prerelease_label": True,
        }
        with patch.object(
            precomputed, "upstream_tree", side_effect=lambda root, c, sha: trees[sha]
        ):
            pairs, broken = precomputed.discover(Path("unused"), commit, [link])
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0]["path"], "iOS/18_5_22F5053f__vs_18_5_22F5053j/README.md")
        self.assertEqual(broken, [link])

    def test_evidence_distinguishes_function_size_from_symbol_and_string_changes(self):
        rows = analyze.evidence("""Symbols:
+ __ZNsendSimApdu_start_block_invoke.7
  __ZNsendSimApdu_close
Functions:
~ __ZNisSimReady : 64 -> 88
CStrings:
- "isSimReady diagnostic"
""")
        self.assertEqual(len(rows), 3)
        self.assertIsNone(rows[0]["function_size"])
        self.assertEqual(
            rows[1]["function_size"], {"symbol": "__ZNisSimReady", "old": 64, "new": 88}
        )
        self.assertEqual(rows[2]["section"], "CStrings")

    def test_boundaries_and_release_channels(self):
        for version in ("14.0", "14.8.1", "16.4.1 (a)", "18.7.11", "26.0", "26.0.1"):
            self.assertTrue(catalog.in_scope({"version": version}), version)
        for version in ("13.7", "26.0.2", "26.1", "27.0", "17.0 beta 1", "17.0 RC", "garbage"):
            self.assertFalse(catalog.in_scope({"version": version}), version)
        for flag in ("beta", "rc", "internal"):
            self.assertFalse(catalog.in_scope({"version": "17.0", flag: True}))

    def test_precomputed_scope_does_not_leak_betas(self):
        source = "\n".join(
            [
                "- [26.0 (23A345) .vs 26.0.1 (23A355)](iOS/pair/README.md)",
                "- [26.0.1 (23A355) .vs 26.1 (23B1)](iOS/next/README.md)",
                "- [17.6 beta 4 (21G5075a) .vs 17.6 RC (21G79)](iOS/rc/TOC.md)",
                "- [13.7 (17H35) .vs 14.0 (18A373)](iOS/older/README.md)",
            ]
        )
        rows = precomputed.entries(source)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["versions"], ["26.0", "26.0.1"])
        self.assertFalse(rows[0]["prerelease_label"])
        self.assertTrue(rows[1]["prerelease_label"])

    def test_diff_does_not_claim_coverage_for_another_device(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            commit = "a" * 40
            reports = root / "sources/ipsw-diffs" / commit
            reports.mkdir(parents=True)
            (reports / "README.md").write_text(
                "- [17.2 (21C62) .vs 17.2.1 (21C66)](iOS/pair/README.md)\n"
            )
            pair = reports / "iOS/pair/README.md"
            pair.parent.mkdir(parents=True)
            pair.write_text(
                "## IPSWs\n\n`iPhone15,2_17.2_21C62_Restore.ipsw`\n`iPhone15,2_17.2.1_21C66_Restore.ipsw`\n"
            )
            with contextlib.closing(sqlite3.connect(root / "catalog.sqlite")) as db:
                db.executescript(
                    "CREATE TABLE release(id TEXT,build TEXT); CREATE TABLE target(release_id TEXT,device TEXT); INSERT INTO release VALUES ('a','21C62'),('b','21C66'); INSERT INTO target VALUES ('a','iPhone14,5'),('b','iPhone14,5');"
                )
            (root / "reports").mkdir()
            with contextlib.redirect_stdout(io.StringIO()):
                precomputed.collect(root, commit)
            result = json.loads((root / "reports/precomputed-diffs.json").read_text())
            self.assertEqual(result["builds_observed_as_diff_inputs"], 0)
            self.assertFalse(result["pairs"][0]["both_inputs_in_stable_iphone_catalog"])
            self.assertEqual(
                result["pairs"][0]["modules"]["CommCenter"]["status"], "not_listed_in_report"
            )
            self.assertEqual(result["firmware_downloaded_bytes"], 0)

    def test_catalog_preserves_devices_ota_prerequisites_and_gaps(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            upstream = root / "sources/appledb"
            upstream.mkdir(parents=True)
            subprocess.run(["git", "init", "-q", str(upstream)], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(upstream),
                    "-c",
                    "user.name=Fixture",
                    "-c",
                    "user.email=fixture@example.invalid",
                    "commit",
                    "-qm",
                    "Fixture",
                    "--allow-empty",
                ],
                check=True,
            )
            record = {
                "version": "17.2.1",
                "build": "21C66",
                "deviceMap": ["iPhone14,5", "iPhone14,4", "iPhone14,2", "iPad13,1"],
                "sources": [
                    {
                        "type": "ipsw",
                        "deviceMap": ["iPhone14,5", "iPhone14,4"],
                        "links": [{"url": "https://example.invalid/shared.ipsw", "active": False}],
                        "hashes": {"sha2-256": "aa"},
                        "size": 100,
                    },
                    {
                        "type": "ota",
                        "deviceMap": ["iPhone14,4"],
                        "boardMap": ["D16AP"],
                        "prerequisiteBuild": "21C62",
                        "links": [{"url": "https://example.invalid/delta.zip"}],
                    },
                ],
            }
            catalog.dump(upstream / "osFiles/iOS/21x/21C66.json", record)
            catalog.dump(
                root / "sources/ipsw-me/iPhone14,5.json",
                {
                    "identifier": "iPhone14,5",
                    "firmwares": [
                        {
                            "version": "17.2.1",
                            "buildid": "21C66",
                            "url": "https://example.invalid/shared.ipsw",
                            "filesize": 100,
                            "sha256sum": "aa",
                        }
                    ],
                },
            )
            with contextlib.redirect_stdout(io.StringIO()):
                catalog.build(root)
            summary = json.loads((root / "reports/catalog-summary.json").read_text())
            self.assertEqual(summary["device_count"], 3)
            self.assertEqual(summary["unique_assets"], {"ipsw": 1, "ota": 1})
            self.assertEqual(summary["without_any_asset_pairs"], 1)
            with contextlib.closing(sqlite3.connect(root / "catalog.sqlite")) as db:
                self.assertEqual(
                    db.execute(
                        "SELECT boards,prerequisites,active FROM delivery d JOIN asset a ON a.id=d.asset WHERE a.kind='ota'"
                    ).fetchone(),
                    ('["D16AP"]', '["21C62"]', -1),
                )
                self.assertEqual(
                    db.execute(
                        "SELECT COUNT(*) FROM delivery d JOIN asset a ON a.id=d.asset WHERE a.kind='ipsw'"
                    ).fetchone()[0],
                    3,
                )


if __name__ == "__main__":
    unittest.main()
