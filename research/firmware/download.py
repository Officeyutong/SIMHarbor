#!/usr/bin/env python3
"""Download only the explicit, checksum-pinned assets in a saved research plan."""

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import urlparse

from catalog import dump


def validate(plan, budget):
    assets = plan["assets"]
    if not assets or len({a["asset"] for a in assets}) != len(assets):
        raise ValueError("Expected unique explicitly selected assets")
    total = 0
    for a in assets:
        if not re.fullmatch(r"[0-9a-f]{24}", a["asset"]) or not re.fullmatch(
            r"[0-9a-f]{64}", a["sha256"]
        ):
            raise ValueError("Missing valid asset ID or SHA256")
        u = urlparse(a["url"])
        if (
            u.scheme != "https"
            or not u.hostname
            or not (
                u.hostname in ("apple.com", "cdn-apple.com")
                or u.hostname.endswith((".apple.com", ".cdn-apple.com"))
            )
            or u.username
            or u.password
        ):
            raise ValueError("Expected an HTTPS Apple firmware URL")
        if isinstance(a["size"], bool) or not isinstance(a["size"], int) or a["size"] <= 0:
            raise ValueError("Invalid archive size")
        total += a["size"]
    if total > budget:
        raise ValueError("Explicit plan exceeds download budget")
    return assets, total


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--budget-gib", type=int, required=True)
    parser.add_argument("--workers", type=int, choices=(1, 2, 4), default=4)
    args = parser.parse_args()
    assets, total = validate(json.loads(args.plan.read_text()), args.budget_gib * 1024**3)
    archive = args.root / "archives"
    archive.mkdir(parents=True, exist_ok=True)
    logs = args.root / "logs"
    logs.mkdir(exist_ok=True)
    pending = sum(
        max(
            0,
            a["size"]
            - min(
                (archive / (a["asset"] + ".ipsw")).stat().st_size,
                (archive / (a["asset"] + ".ipsw")).stat().st_blocks * 512,
            ),
        )
        if (archive / (a["asset"] + ".ipsw")).exists()
        else a["size"]
        for a in assets
    )
    if shutil.disk_usage(archive).free < pending + 50 * 1024**3:
        raise SystemExit("Insufficient free space for selected archives plus 50 GiB reserve")
    state = {"planned_bytes": total, "results": {}}

    def one(a):
        path = archive / (a["asset"] + ".ipsw")
        if path.exists() and path.stat().st_size == a["size"] and sha256(path) == a["sha256"]:
            return {
                "status": "verified",
                "path": str(path.resolve()),
                "bytes": a["size"],
                "cached": True,
            }
        command = [
            "aria2c",
            "--file-allocation=none",
            "--allow-overwrite=false",
            "--auto-file-renaming=false",
            "--continue=true",
            "--check-integrity=true",
            "--max-connection-per-server=8",
            "--split=8",
            "--min-split-size=4M",
            "--max-tries=5",
            "--retry-wait=5",
            "--timeout=30",
            "--summary-interval=0",
            "--console-log-level=warn",
            "--download-result=hide",
            "--checksum=sha-256=" + a["sha256"],
            "--dir=" + str(archive.resolve()),
            "--out=" + path.name,
            a["url"],
        ]
        with (logs / ("download-" + a["asset"] + ".log")).open("a") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode or not path.exists() or path.stat().st_size != a["size"]:
            return {
                "status": "failed",
                "exit_code": result.returncode,
                "bytes": path.stat().st_size if path.exists() else 0,
            }
        if sha256(path) != a["sha256"]:
            return {"status": "checksum_failed", "bytes": path.stat().st_size}
        return {
            "status": "verified",
            "path": str(path.resolve()),
            "bytes": a["size"],
            "cached": False,
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(one, a): a for a in assets}
        for future in concurrent.futures.as_completed(jobs):
            a = jobs[future]
            try:
                state["results"][a["asset"]] = future.result()
            except Exception as error:
                state["results"][a["asset"]] = {"status": "failed", "error": str(error)}
            dump(args.root / "reports/targeted-download-status.json", state)
            print(a["version"], a["device"], state["results"][a["asset"]]["status"], flush=True)
    if any(r["status"] != "verified" for r in state["results"].values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
