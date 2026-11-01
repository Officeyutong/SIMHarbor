#!/usr/bin/env python3
"""Extract selected targets from one verified local IPSW using read-only APFS mounts."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import zipfile

from catalog import dump
from download import sha256

MODULES = (
    "libCommCenterMCommandDrivers.dylib",
    "libCommCenterKCommandDrivers.dylib",
    "libCommCenterBase.dylib",
)
SUPPORT = Path("System/Library/Frameworks/CoreTelephony.framework/Support")


def select_identity(manifest, boards):
    """Choose the selected board's normal erase identity, excluding RecoveryOS."""
    candidates = [
        identity
        for identity in manifest["BuildIdentities"]
        if identity["Info"].get("Variant") == "Customer Erase Install (IPSW)"
        and (not boards or identity["Info"].get("DeviceClass", "").lower() in boards)
    ]
    if len(candidates) != 1:
        raise ValueError("Cannot uniquely select a customer erase identity for this device")
    return candidates[0]


def extract(root, plan, asset_id):
    asset = next(a for a in plan["assets"] if a["asset"] == asset_id)
    status = json.loads((root / "reports/targeted-download-status.json").read_text())[
        "results"
    ].get(asset_id, {})
    if status.get("status") != "verified":
        raise ValueError("Archive has not passed download checksum verification")
    archive = root / "archives" / (asset_id + ".ipsw")
    if archive.stat().st_size != asset["size"] or sha256(archive) != asset["sha256"]:
        raise ValueError("Verified archive was changed")
    ipsw = (root / "tools/ipsw").resolve()
    apfs = (root / "tools/apfs-fuse-build/apfs-fuse").resolve()
    output = root / "artifacts" / asset_id
    output.mkdir(parents=True, exist_ok=True)
    work_parent = root / "work"
    work_parent.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="extract-" + asset_id + "-", dir=work_parent)).resolve()
    result = {
        "asset": asset_id,
        "version": asset["version"],
        "build": asset["build"],
        "device": asset["device"],
        "archive_sha256": asset["sha256"],
        "components": [],
        "targets": {},
        "errors": [],
    }
    mounted = []
    log_path = root / "logs" / ("extract-" + asset_id + ".log")

    def run(command, log, timeout=600):
        subprocess.run(
            [str(x) for x in command],
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=True,
        )

    def save(path, name):
        destination = output / name
        if path.stat().st_size == 0:
            raise ValueError("Target has no file content: " + name)
        shutil.copyfile(path, destination)
        result["targets"][name] = {
            "path": str(destination.resolve()),
            "size": destination.stat().st_size,
            "sha256": sha256(destination),
        }

    try:
        with zipfile.ZipFile(archive) as z, log_path.open("a") as log:
            raw = z.read("BuildManifest.plist")
            (output / "BuildManifest.plist").write_bytes(raw)
            manifest = plistlib.loads(raw)
            if (
                manifest["ProductBuildVersion"] != asset["build"]
                or asset["device"] not in manifest["SupportedProductTypes"]
            ):
                raise ValueError("BuildManifest does not match selected build/device")
            with sqlite3.connect(root / "catalog.sqlite") as db:
                row = db.execute(
                    "SELECT metadata FROM device WHERE id=?", (asset["device"],)
                ).fetchone()
            db.close()
            boards = (json.loads(row[0]).get("board") or []) if row else []
            if isinstance(boards, str):
                boards = [boards]
            identity = select_identity(manifest, {board.lower() for board in boards})
            result["identity"] = identity["Info"]
            # Extract one normal customer identity, never a RecoveryOS replacement.
            components = {}
            for key in ("OS", "Cryptex1,SystemOS"):
                component = identity["Manifest"].get(key)
                if component:
                    components.setdefault(component["Info"]["Path"], set()).add(key)
            for filename, kinds in components.items():
                if Path(filename).name != filename:
                    raise ValueError("Unexpected nested filesystem component path")
                dmg = work / filename
                info = z.getinfo(filename)
                if info.file_size > 40 * 1024**3:
                    raise ValueError("Filesystem image exceeds extraction budget")
                with z.open(info) as source, dmg.open("wb") as destination:
                    shutil.copyfileobj(source, destination, 4 * 1024 * 1024)
                record = {
                    "archive_path": filename,
                    "kinds": sorted(kinds),
                    "bytes": dmg.stat().st_size,
                    "sha256": sha256(dmg),
                }
                result["components"].append(record)
                with dmg.open("rb") as f:
                    encrypted = f.read(4) == b"AEA1"
                if encrypted:
                    decrypt = work / "decrypted"
                    decrypt.mkdir(exist_ok=True)
                    run([ipsw, "fw", "aea", dmg, "--output", decrypt], log)
                    candidates = [
                        p for p in decrypt.iterdir() if p.is_file() and p.suffix == ".dmg"
                    ]
                    if len(candidates) != 1:
                        raise ValueError("Cannot uniquely identify decrypted DMG")
                    dmg = candidates[0]
                    record["decrypted_sha256"] = sha256(dmg)
                mount = work / ("mount-" + str(len(result["components"])))
                mount.mkdir()
                try:
                    run([apfs, dmg, mount], log, timeout=90)
                    if not os.path.ismount(mount):
                        raise ValueError("APFS mount did not become ready")
                    mounted.append(mount)
                    fs = mount / "root" if (mount / "root").is_dir() else mount
                    core = fs / SUPPORT / "CommCenter"
                    if core.is_file():
                        save(core, "CommCenter")
                    for name in MODULES:
                        path = fs / SUPPORT / name
                        if path.is_file() and path.stat().st_size > 4096:
                            save(path, name)
                    for directory in (
                        fs / "System/Library/Caches/com.apple.dyld",
                        fs / "System/Library/dyld",
                    ):
                        if not directory.is_dir():
                            continue
                        for arch in ("arm64e", "arm64"):
                            cache = directory / ("dyld_shared_cache_" + arch)
                            if not cache.is_file():
                                continue
                            for name in MODULES:
                                if name in result["targets"]:
                                    continue
                                try:
                                    run(
                                        [
                                            ipsw,
                                            "dyld",
                                            "extract",
                                            cache,
                                            name,
                                            "--slide",
                                            "--output",
                                            output,
                                        ],
                                        log,
                                    )
                                    path = output / name
                                    if not path.is_file():
                                        raise ValueError("Extractor did not produce " + name)
                                    result["targets"][name] = {
                                        "path": str(path.resolve()),
                                        "size": path.stat().st_size,
                                        "sha256": sha256(path),
                                        "cache": str(cache.relative_to(fs)),
                                    }
                                except (subprocess.SubprocessError, ValueError) as error:
                                    result["errors"].append(
                                        {"component": filename, "target": name, "error": str(error)}
                                    )
                finally:
                    if os.path.ismount(mount):
                        run(["fusermount3", "-u", mount], log, timeout=30)
                    if mount in mounted:
                        mounted.remove(mount)
                if encrypted:
                    shutil.rmtree(work / "decrypted")
                (work / filename).unlink()
        required = ("CommCenter", "libCommCenterMCommandDrivers.dylib", "libCommCenterBase.dylib")
        result["status"] = (
            "extracted" if all(name in result["targets"] for name in required) else "incomplete"
        )
    except Exception as error:
        result["status"] = "failed"
        result["errors"].append({"error": str(error)})
    finally:
        # Never recursively remove a live filesystem mount after a failed unmount.
        if not mounted and not any(os.path.ismount(p) for p in work.glob("mount-*")):
            shutil.rmtree(work)
        else:
            result["retained_work"] = str(work)
        dump(output / "extraction.json", result)
    print(asset["version"], result["status"], ", ".join(result["targets"]), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--asset", required=True)
    args = parser.parse_args()
    result = extract(args.root.resolve(), json.loads(args.plan.read_text()), args.asset)
    if result["status"] != "extracted":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
