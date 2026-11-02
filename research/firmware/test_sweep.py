#!/usr/bin/env python3
"""Check board coverage, complete-source selection and archive deletion policy."""

import hashlib
import json
from pathlib import Path
import plistlib
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

from catalog import dump
from sweep import identity_groups, plan_sweep, run_sweep
from sweep_report import report
from sweep_analysis import first_return_prefix, normalize_local_branches


class SweepTests(unittest.TestCase):
    def setUp(self):
        disk = patch("sweep.shutil.disk_usage", return_value=Mock(free=1024**4))
        disk.start()
        self.addCleanup(disk.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.corpus = Path(self.temp.name) / "corpus"
        self.corpus.mkdir()
        (self.corpus / "tools").mkdir()
        (self.corpus / "tools/offline-resolver").write_bytes(b"fixture runner")
        self.root = self.corpus / "sweep"
        db = sqlite3.connect(self.corpus / "catalog.sqlite")
        db.executescript("""CREATE TABLE device(id TEXT,metadata TEXT);
        CREATE TABLE release(id TEXT PRIMARY KEY,version TEXT,build TEXT,rsr INTEGER,released TEXT);
        CREATE TABLE target(release_id TEXT,device TEXT);
        CREATE TABLE asset(id TEXT,kind TEXT,url TEXT,size INTEGER,hashes TEXT);
        CREATE TABLE delivery(asset TEXT,release_id TEXT,device TEXT,boards TEXT,prerequisites TEXT,active INTEGER,provider TEXT,source TEXT);""")
        for identifier, board in [("iPhone10,1", "D20AP"), ("iPhone10,4", "D201AP")]:
            db.execute(
                "INSERT INTO device VALUES (?,?)",
                (identifier, json.dumps({"board": board, "arch": "arm64"})),
            )
        db.commit()
        db.close()

    def add(self, device, build, version, kind, prerequisites=(), asset="a" * 24, rsr=False):
        with sqlite3.connect(self.corpus / "catalog.sqlite") as db:
            db.execute(
                "INSERT OR IGNORE INTO release VALUES (?,?,?,?,?)",
                (build, version, build, rsr, "2023-01-01"),
            )
            db.execute("INSERT INTO target VALUES (?,?)", (build, device))
            if kind:
                if not db.execute("SELECT 1 FROM asset WHERE id=?", (asset,)).fetchone():
                    db.execute(
                        "INSERT INTO asset VALUES (?,?,?,?,?)",
                        (
                            asset,
                            kind,
                            "https://updates.cdn-apple.com/" + asset,
                            3,
                            json.dumps({"sha256": hashlib.sha256(b"zip").hexdigest()}),
                        ),
                    )
                db.execute(
                    "INSERT INTO delivery VALUES (?,?,?,?,?,?,?,?)",
                    (
                        asset,
                        build,
                        device,
                        "[]",
                        json.dumps(prerequisites),
                        1,
                        "fixture",
                        "fixture",
                    ),
                )

        db.close()

    def plan(self):
        with patch("sweep.subprocess.check_output", return_value="fixture-commit\n"):
            return plan_sweep(self.corpus, self.root, 16)

    def test_source_selection_preserves_gaps_and_deduplicates_shared_archives(self):
        self.add("iPhone10,1", "20A", "16.0", "ipsw")
        self.add("iPhone10,4", "20A", "16.0", "ipsw")
        self.add("iPhone10,1", "20B", "16.1", "ota", asset="b" * 24)
        self.add("iPhone10,4", "20C", "16.2", "ota", prerequisites=["20B"], asset="c" * 24)
        self.add("iPhone10,1", "21A", "17.0", "ipsw", asset="d" * 24)
        plan = self.plan()
        self.assertEqual({a["asset"] for a in plan["assets"]}, {"a" * 24, "b" * 24})
        self.assertEqual(len(plan["assets"][0]["targets"]), 2)
        self.assertTrue(any(g["build"] == "20C" for g in plan["gaps"]))
        self.assertEqual(plan["scope"]["targets"], 4)

    def test_board_equivalence_requires_same_component_paths_and_arch(self):
        self.add("iPhone10,1", "20A", "16.0", "ipsw")
        self.add("iPhone10,4", "20A", "16.0", "ipsw")
        asset = self.plan()["assets"][0]
        manifest = {
            "ProductBuildVersion": "20A",
            "SupportedProductTypes": ["iPhone10,1", "iPhone10,4"],
            "BuildIdentities": [
                {
                    "Info": {"Variant": "Customer Erase Install (IPSW)", "DeviceClass": board},
                    "Manifest": {"OS": {"Info": {"Path": "system.dmg"}}},
                }
                for board in ["D20AP", "D201AP"]
            ],
        }
        archive = self.root / "fixture.ipsw"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("BuildManifest.plist", plistlib.dumps(manifest))
        groups = identity_groups(self.root, asset, archive)
        self.assertEqual(len(groups), 1)
        self.assertEqual(len(groups[0]["targets"]), 2)
        with sqlite3.connect(self.root / "catalog.sqlite") as db:
            db.execute(
                "UPDATE device SET metadata=? WHERE id=?",
                (json.dumps({"board": "D201AP", "arch": "arm64e"}), "iPhone10,4"),
            )
        db.close()
        self.assertEqual(len(identity_groups(self.root, asset, archive)), 2)
        with self.assertRaises(ValueError):
            identity_groups(self.root, asset | {"build": "wrong"}, archive)

    def test_manifest_rejects_bad_delivery_without_discarding_valid_targets(self):
        self.add("iPhone10,1", "20A", "16.0", "ipsw")
        self.add("iPhone10,4", "20A", "16.0", "ipsw")
        asset = self.plan()["assets"][0]
        manifest = {
            "ProductBuildVersion": "20A",
            "SupportedProductTypes": ["iPhone10,1"],
            "BuildIdentities": [
                {
                    "Info": {"Variant": "Customer Erase Install (IPSW)", "DeviceClass": "D20AP"},
                    "Manifest": {"OS": {"Info": {"Path": "system.dmg"}}},
                }
            ],
        }
        archive = self.root / "fixture.ipsw"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("BuildManifest.plist", plistlib.dumps(manifest))
        with self.assertRaises(ValueError):
            identity_groups(self.root, asset, archive)
        excluded = []
        groups = identity_groups(self.root, asset, archive, excluded=excluded)
        self.assertEqual([t["device"] for t in groups[0]["targets"]], ["iPhone10,1"])
        self.assertEqual([t["device"] for t in excluded], ["iPhone10,4"])
        dump(
            self.root / "reports/state.json",
            {
                "results": {
                    asset["asset"]: {
                        "status": "analyzed_deleted",
                        "analysis": {
                            "groups": [groups[0] | {"resolver": {"status": "resolved"}}],
                            "excluded_targets": excluded,
                        },
                    }
                }
            },
        )
        summary = report(self.root)
        self.assertEqual(summary["analyzed_device_build_targets"], 1)
        self.assertEqual(summary["static_resolved_device_build_targets"], 1)
        saved = json.loads((self.root / "reports/summary.json").read_text())
        self.assertEqual(saved["manifest_source_gaps"], excluded)
        # With no supported targets, an asset still fails; it cannot be deleted as analyzed.
        bad = asset | {"targets": [t for t in asset["targets"] if t["device"] == "iPhone10,4"]}
        with self.assertRaises(ValueError):
            identity_groups(self.root, bad, archive, excluded=[])

    def test_readiness_normalization_preserves_constants_and_memory_offsets(self):
        original = "0000: cmp w0, #9\n0004: b.hi #0x1010\n0008: ldr w8, [x0, #4]\n0010: ret\n"
        relocated = original.replace("#0x1010", "#0x2010")
        self.assertEqual(
            normalize_local_branches(original, 0x1000, 20),
            normalize_local_branches(relocated, 0x2000, 20),
        )
        self.assertNotEqual(
            normalize_local_branches(original, 0x1000, 20),
            normalize_local_branches(original.replace("#9", "#10"), 0x1000, 20),
        )
        self.assertNotEqual(
            normalize_local_branches(original, 0x1000, 20),
            normalize_local_branches(original.replace("#4]", "#8]"), 0x1000, 20),
        )
        self.assertIn(
            "#0x9999", normalize_local_branches(original.replace("#0x1010", "#0x9999"), 0x1000, 20)
        )
        with self.assertRaises(ValueError):
            normalize_local_branches("unparsed instruction", 0x1000, 20)
        prefix = first_return_prefix("0000: cmp w0, #9\n0004: ret\n0008: bl #0x9999\n")
        self.assertEqual(prefix, "0000: cmp w0, #9\n0004: ret\n")
        self.assertIsNone(first_return_prefix("0000: br x8\n"))

    def test_archive_deleted_only_after_completed_analysis(self):
        self.add("iPhone10,1", "20A", "16.0", "ipsw")
        plan = self.plan()
        asset = plan["assets"][0]
        archive = self.root / "archives" / (asset["asset"] + ".ipsw")

        def download(a, folder, logs):
            archive.write_bytes(b"zip")
            return {"status": "verified", "path": str(archive), "cached": False}

        with (
            patch("sweep.download_one", side_effect=download),
            patch(
                "sweep.analyze_asset",
                return_value={"status": "incomplete", "error": "missing targets"},
            ),
        ):
            run_sweep(self.corpus, self.root, 1, None, None)
        self.assertTrue(archive.is_file())
        self.assertEqual(
            json.loads((self.root / "reports/state.json").read_text())["results"][asset["asset"]][
                "status"
            ],
            "analysis_failed",
        )
        with (
            patch("sweep.download_one", side_effect=download),
            patch("sweep.analyze_asset", return_value={"status": "analyzed", "groups": []}),
        ):
            run_sweep(self.corpus, self.root, 1, None, None)
        self.assertFalse(archive.exists())
        summary = report(self.root)
        self.assertEqual(summary["asset_statuses"], {"analyzed_deleted": 1})
        # A result without per-board evidence must not inflate target coverage.
        self.assertEqual(summary["analyzed_device_build_targets"], 0)


if __name__ == "__main__":
    unittest.main()
