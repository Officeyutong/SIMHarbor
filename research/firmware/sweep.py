#!/usr/bin/env python3
"""Plan and run a bounded, resumable firmware sweep; never alter application code.

IPSWs cover every catalog target for which a restore image exists. Otherwise
select a full OTA, or one largest RSR delivery. No delta is called a full image.
Successful analysis preserves modules/reports and deletes the downloaded archive.
"""

import argparse
import collections
from contextlib import closing
import concurrent.futures
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import time
import zipfile

from catalog import dump
from download import download_one, sha256, validate
from extract import extract, MODULES
from macho_inspection import inspect
from offline_resolver import prepare


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def plan_sweep(corpus, root, major):
    root.mkdir(parents=True, exist_ok=True)
    for name in ["reports", "archives", "logs", "work", "artifacts", "analyses"]:
        (root / name).mkdir(exist_ok=True)
    with (
        closing(sqlite3.connect(corpus / "catalog.sqlite")) as source,
        closing(sqlite3.connect(root / "catalog.sqlite")) as db,
    ):
        source.backup(db)
    db = sqlite3.connect(root / "catalog.sqlite")
    db.row_factory = sqlite3.Row
    targets = [
        dict(r)
        for r in db.execute(
            "SELECT r.id release_id,r.version,r.build,r.rsr,t.device,r.released FROM target t JOIN release r ON r.id=t.release_id WHERE r.version LIKE ? ORDER BY r.released,r.build,t.device",
            (str(major) + ".%",),
        )
    ]
    assets, gaps = {}, []
    for target in targets:
        deliveries = [
            dict(r)
            for r in db.execute(
                "SELECT a.*,d.boards,d.prerequisites,d.active,d.provider,d.source FROM delivery d JOIN asset a ON a.id=d.asset WHERE d.release_id=? AND d.device=?",
                (target["release_id"], target["device"]),
            )
        ]
        ipsws = [d for d in deliveries if d["kind"] == "ipsw"]
        full_otas = [
            d for d in deliveries if d["kind"] == "ota" and not json.loads(d["prerequisites"])
        ]
        choices = (
            ipsws or sorted(full_otas, key=lambda d: (d["active"] != 1, -(d["size"] or 0)))[:1]
        )
        if not choices and target["rsr"]:
            choices = sorted(deliveries, key=lambda d: (d["active"] != 1, -(d["size"] or 0)))[:1]
        if not choices:
            gaps.append(target | {"reason": "No IPSW or full OTA source; no fabricated coverage"})
            continue
        for delivery in choices:
            hashes = json.loads(delivery["hashes"])
            if not hashes.get("sha256") or not delivery["size"]:
                gaps.append(
                    target | {"reason": "Missing published SHA256 or size", "asset": delivery["id"]}
                )
                continue
            key = delivery["id"]
            if key not in assets:
                assets[key] = {
                    "asset": key,
                    "kind": delivery["kind"],
                    "url": delivery["url"],
                    "size": delivery["size"],
                    "sha256": hashes["sha256"],
                    "version": target["version"],
                    "build": target["build"],
                    "device": target["device"],
                    "rsr": bool(target["rsr"]),
                    "targets": [],
                }
            entry = target | {
                "boards": json.loads(delivery["boards"]),
                "prerequisites": json.loads(delivery["prerequisites"]),
            }
            if entry not in assets[key]["targets"]:
                assets[key]["targets"].append(entry)
    ordered = sorted(
        assets.values(),
        key=lambda a: (a["kind"] != "ipsw", a["version"] != "16.5.1", a["device"], a["build"]),
    )
    result = {
        "schema_version": 1,
        "created": now(),
        "scope": {
            "major": major,
            "beta": False,
            "rc": False,
            "rsr": True,
            "devices": len({t["device"] for t in targets}),
            "builds": len({t["release_id"] for t in targets}),
            "targets": len(targets),
        },
        "source_database_sha256": sha256(root / "catalog.sqlite"),
        "source_commit": subprocess.check_output(
            ["git", "-C", str(corpus / "sources/appledb"), "rev-parse", "HEAD"], text=True
        ).strip(),
        "assets": ordered,
        "total_bytes": sum(a["size"] for a in ordered),
        "gaps": gaps,
    }
    validate(result, result["total_bytes"])
    dump(root / "reports/plan.json", result)
    db.close()
    for name in ["tools"]:
        link = root / name
        if not link.exists():
            link.symlink_to((corpus / name).resolve(), target_is_directory=True)
    print(
        json.dumps(
            {
                "assets": len(ordered),
                "bytes": result["total_bytes"],
                "scope": result["scope"],
                "no_source_targets": len(gaps),
            }
        ),
        flush=True,
    )
    return result


def identity_groups(root, asset, archive):
    """Bind every target board to actual manifest OS paths and cache architecture."""
    with zipfile.ZipFile(archive) as z:
        manifest = plistlib.loads(z.read("BuildManifest.plist"))
    if manifest["ProductBuildVersion"] != asset["build"]:
        raise ValueError("Manifest build mismatch")
    groups = {}
    with closing(sqlite3.connect(root / "catalog.sqlite")) as db:
        for target in asset["targets"]:
            if target["device"] not in manifest["SupportedProductTypes"]:
                raise ValueError("Manifest device mismatch")
            metadata = json.loads(
                db.execute(
                    "SELECT metadata FROM device WHERE id=?", (target["device"],)
                ).fetchone()[0]
            )
            boards = metadata.get("board") or []
            boards = [boards] if isinstance(boards, str) else boards
            if target["boards"]:
                boards = [b for b in boards if b.lower() in {x.lower() for x in target["boards"]}]
            if not boards:
                raise ValueError("Missing board metadata")
            for board in boards:
                identities = [
                    i
                    for i in manifest["BuildIdentities"]
                    if i["Info"].get("Variant") == "Customer Erase Install (IPSW)"
                    and i["Info"].get("DeviceClass", "").lower() == board.lower()
                ]
                if len(identities) != 1:
                    raise ValueError("Ambiguous erase identity: " + board)
                identity = identities[0]
                components = tuple(
                    sorted(
                        {
                            identity["Manifest"][k]["Info"]["Path"]
                            for k in ["OS", "Cryptex1,SystemOS"]
                            if k in identity["Manifest"]
                        }
                    )
                )
                if not components:
                    raise ValueError("No OS component")
                key = (metadata.get("arch"), components)
                group = groups.setdefault(
                    key,
                    {
                        "device": target["device"],
                        "board": board,
                        "arch": metadata.get("arch"),
                        "components": list(components),
                        "targets": [],
                    },
                )
                group["targets"].append(target | {"board": board})
    return list(groups.values())


def replay(root, folder, destination):
    """Keep results/provenance, remove the reproducible temporary memory model."""
    destination.mkdir(parents=True, exist_ok=True)
    model = Path(tempfile.mkdtemp(prefix="replay-", dir=root / "work"))
    try:
        prepared = prepare(folder, model)
        runner = root / "tools/offline-resolver"
        value = json.loads(
            subprocess.check_output(
                [str(runner), str(model / "input.json")], timeout=300, text=True
            )
        )
        value["model"] = prepared["model"]
        value["fixups"] = {k: prepared[k]["fixups"] for k in ["cc", "driver"]}
        value["runner_sha256"] = sha256(runner)
        dump(destination / "resolver.json", value)
        return {
            "status": "resolved" if value["complete"] else "unresolved",
            "errors": value["errors"],
        }
    except Exception as error:
        dump(destination / "resolver.json", {"complete": False, "model_error": str(error)})
        return {"status": "model_error", "error": str(error)}
    finally:
        shutil.rmtree(model)


def inspect_ota(root, asset, archive):
    """Extract standalone payloads/caches only; never pretend delta bytes are images."""
    output = root / "artifacts" / asset["asset"]
    output.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="ota-", dir=root / "work"))
    ipsw = root / "tools/ipsw"
    result = {
        "asset": asset["asset"],
        "kind": "ota",
        "rsr": asset["rsr"],
        "targets": asset["targets"],
        "status": "incomplete",
    }
    try:
        with (root / "logs" / ("ota-" + asset["asset"] + ".log")).open("a") as log:
            # The listing is evidence even if standalone cache extraction fails.
            listing = subprocess.run(
                [str(ipsw), "ota", "ls", str(archive), "--payload", "--json"],
                stdout=subprocess.PIPE,
                stderr=log,
                timeout=600,
            )
            (output / "payload-listing.jsonl").write_bytes(listing.stdout)
            result["listing_exit"] = listing.returncode
            extraction = subprocess.run(
                [
                    str(ipsw),
                    "ota",
                    "extract",
                    str(archive),
                    "--pattern",
                    r"(^|/)(CommCenter|libCommCenter(MCommandDrivers|KCommandDrivers|Base)\.dylib)$",
                    "--confirm",
                    "--output",
                    str(work),
                ],
                stdout=log,
                stderr=log,
                timeout=900,
            )
            result["payload_extract_exit"] = extraction.returncode
            cache_result = subprocess.run(
                [
                    str(ipsw),
                    "ota",
                    "extract",
                    str(archive),
                    "--dyld",
                    "--json",
                    "--output",
                    str(work),
                ],
                stdout=subprocess.PIPE,
                stderr=log,
                timeout=1800,
            )
            (output / "cache-extraction.json").write_bytes(cache_result.stdout)
            result["cache_extract_exit"] = cache_result.returncode
            for name in ("CommCenter", *MODULES):
                candidates = [
                    p for p in work.rglob(name) if p.is_file() and p.stat().st_size > 4096
                ]
                if candidates:
                    shutil.copyfile(candidates[0], output / name)
            caches = [
                p
                for p in work.rglob("dyld_shared_cache_*")
                if p.is_file() and p.name in ["dyld_shared_cache_arm64e", "dyld_shared_cache_arm64"]
            ]
            if len(caches) > 1:
                raise ValueError(
                    "Multiple OTA cache architectures require separate analysis groups"
                )
            for cache in caches:
                for name in MODULES:
                    if (output / name).exists():
                        continue
                    subprocess.run(
                        [
                            str(ipsw),
                            "dyld",
                            "extract",
                            str(cache),
                            name,
                            "--slide",
                            "--output",
                            str(output),
                        ],
                        stdout=log,
                        stderr=log,
                        check=True,
                        timeout=600,
                    )
        required = ["CommCenter", "libCommCenterMCommandDrivers.dylib", "libCommCenterBase.dylib"]
        if all((output / name).is_file() for name in required):
            inspect(root, output)
            result["resolver"] = replay(root, output, root / "analyses" / asset["asset"])
            result["status"] = "analyzed"
        else:
            result["error"] = (
                "Standalone targets unavailable; RSR/delta reconstruction or cryptex extraction required. Not covered."
            )
    except Exception as error:
        result["error"] = str(error)
    finally:
        shutil.rmtree(work)
        dump(output / "ota-analysis.json", result)
    return result


def analyze_asset(root, asset):
    archive = root / "archives" / (asset["asset"] + (".zip" if asset["kind"] == "ota" else ".ipsw"))
    if asset["kind"] == "ota":
        return inspect_ota(root, asset, archive)
    groups = identity_groups(root, asset, archive)
    report = {"asset": asset["asset"], "status": "analyzed", "groups": []}
    for index, group in enumerate(groups):
        output = root / "artifacts" / asset["asset"] / ("group-" + str(index))
        chosen = asset | {"device": group["device"]}
        result = extract(
            root,
            {"assets": [chosen]},
            asset["asset"],
            board=group["board"],
            output=output,
            arch=group["arch"],
        )
        if result["status"] != "extracted":
            raise RuntimeError("Target extraction incomplete: " + json.dumps(result["errors"]))
        inspect(root, output)
        group["resolver"] = replay(
            root, output, root / "analyses" / asset["asset"] / ("group-" + str(index))
        )
        group["modules"] = {
            name: {"sha256": sha256(output / name), "bytes": (output / name).stat().st_size}
            for name in ("CommCenter", *MODULES)
            if (output / name).is_file()
        }
        report["groups"].append(group)
    dump(root / "analyses" / asset["asset"] / "analysis.json", report)
    return report


def run_sweep(corpus, root, workers, kind, limit):
    with (root / "run.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return run_locked(corpus, root, workers, kind, limit)


def run_locked(corpus, root, workers, kind, limit):
    plan = json.loads((root / "reports/plan.json").read_text())
    validate(plan, plan["total_bytes"])
    state_path = root / "reports/state.json"
    state = (
        json.loads(state_path.read_text())
        if state_path.exists()
        else {"started": now(), "results": {}}
    )
    receipts_path = root / "reports/targeted-download-status.json"
    receipts = json.loads(receipts_path.read_text()) if receipts_path.exists() else {"results": {}}
    digest = sha256(root / "reports/plan.json")
    if state.get("plan_sha256") not in (None, digest):
        raise ValueError("Saved plan changed; use a separate sweep directory")
    state["plan_sha256"] = digest
    state.setdefault("runs", []).append(
        {
            "started": now(),
            "pid": os.getpid(),
            "runner_sha256": sha256(root / "tools/offline-resolver"),
            "source_sha256": {
                name: sha256(Path(__file__).with_name(name))
                for name in [
                    "sweep.py",
                    "download.py",
                    "extract.py",
                    "macho_inspection.py",
                    "offline_resolver.py",
                ]
            },
        }
    )
    assets = [
        a
        for a in plan["assets"]
        if (not kind or a["kind"] == kind)
        and state["results"].get(a["asset"], {}).get("status") != "analyzed_deleted"
    ]
    if limit:
        assets = assets[:limit]
    for offset in range(0, len(assets), workers):
        if (root / "STOP_AFTER_BATCH").exists():
            state["paused_reason"] = "Checkpoint requested; no mounts or active downloads retained"
            dump(state_path, state)
            return
        batch = assets[offset : offset + workers]
        reserve = 100 * 1024**3
        retained = sum(p.stat().st_size for p in (root / "archives").glob("*") if p.is_file())
        if (
            shutil.disk_usage(root).free < reserve + sum(a["size"] for a in batch)
            or retained > 80 * 1024**3
        ):
            state["paused_reason"] = "Disk reserve or failed-archive retention limit"
            dump(state_path, state)
            raise RuntimeError(state["paused_reason"])
        state["active_batch"] = [a["asset"] for a in batch]
        state["updated"] = now()
        dump(state_path, state)
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {}
            for asset in batch:
                prior = corpus / "archives" / (asset["asset"] + ".ipsw")
                dest = (
                    root
                    / "archives"
                    / (asset["asset"] + (".zip" if asset["kind"] == "ota" else ".ipsw"))
                )
                if asset["kind"] == "ipsw" and prior.is_file() and not dest.exists():
                    os.link(prior, dest)
                futures[pool.submit(download_one, asset, root / "archives", root / "logs")] = asset
            for future in concurrent.futures.as_completed(futures):
                asset = futures[future]
                aid = asset["asset"]
                try:
                    receipt = future.result()
                except Exception as error:
                    receipt = {"status": "failed", "error": str(error)}
                receipts["results"][aid] = receipt
                dump(receipts_path, receipts)
                state["results"][aid] = {
                    "status": receipt["status"],
                    "download": receipt,
                    "updated": now(),
                }
                dump(state_path, state)
                print(
                    now(),
                    asset["version"],
                    asset["device"],
                    "download",
                    receipt["status"],
                    flush=True,
                )
        for asset in batch:
            aid = asset["asset"]
            entry = state["results"][aid]
            if entry["status"] != "verified":
                continue
            entry["status"] = "analyzing"
            dump(state_path, state)
            try:
                result = analyze_asset(root, asset)
                entry["analysis"] = result
                if result["status"] != "analyzed":
                    raise RuntimeError(result.get("error", "Incomplete analysis"))
                archive = Path(entry["download"]["path"])
                prior = corpus / "archives" / archive.name
                # Delete only the verified downloaded input, never analysis targets.
                if prior.is_file() and os.path.samefile(prior, archive):
                    prior.unlink()
                    entry["prior_cached_archive_deleted"] = True
                archive.unlink()
                entry["status"] = "analyzed_deleted"
                entry["archive_deleted_at"] = now()
            except Exception as error:
                entry["status"] = "analysis_failed"
                entry["error"] = str(error)
            entry["updated"] = now()
            dump(state_path, state)
            print(now(), asset["version"], asset["device"], entry["status"], flush=True)
        state["counts"] = dict(collections.Counter(x["status"] for x in state["results"].values()))
        dump(state_path, state)
    state["finished_selected_queue"] = now()
    state.pop("active_batch", None)
    dump(state_path, state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--major", type=int, default=16)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--kind", choices=["ipsw", "ota"])
    parser.add_argument("--limit", type=int)
    parser.add_argument("--workers", type=int, choices=[1, 2, 4], default=4)
    args = parser.parse_args()
    corpus = args.corpus.resolve()
    root = args.root.resolve()
    if args.plan:
        plan_sweep(corpus, root, args.major)
    if args.run:
        run_sweep(corpus, root, args.workers, args.kind, args.limit)
    if not args.plan and not args.run:
        parser.error("Specify --plan or --run")


if __name__ == "__main__":
    main()
