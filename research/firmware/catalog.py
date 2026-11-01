#!/usr/bin/env python3
"""Index public firmware metadata without treating indexing as binary validation."""

import argparse
import collections
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import time
import urllib.request

DEVICE = re.compile(r"iPhone\d+,\d+\Z")
VERSION = re.compile(r"(\d+)(?:\.(\d+))?(?:\.(\d+))?(?: \(([a-z])\))?\Z")


def version_key(value):
    match = VERSION.fullmatch(value)
    return tuple(int(n or 0) for n in match.groups()[:3]) if match else None


def in_scope(record):
    key = version_key(record.get("version", ""))
    return bool(
        key
        and (14, 0, 0) <= key <= (26, 0, 1)
        and not record.get("beta")
        and not record.get("rc")
        and not record.get("internal")
    )


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def fetch(url, destination):
    """Cache an immutable source response; explicit refresh requires deleting it."""
    if destination.exists():
        return json.loads(destination.read_text())
    for attempt in range(3):
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": "SIMHarbor-firmware-research"}
            )
            with urllib.request.urlopen(request, timeout=45) as response:
                data = json.load(response)
            dump(destination, data)
            return data
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def sync_ipsw_me(root):
    devices = fetch("https://api.ipsw.me/v4/devices?type=ipsw", root / "sources/ipsw-devices.json")
    identifiers = sorted(d["identifier"] for d in devices if DEVICE.fullmatch(d["identifier"]))

    def one(identifier):
        url = f"https://api.ipsw.me/v4/device/{identifier}?type=ipsw"
        fetch(url, root / "sources/ipsw-me" / (identifier + ".json"))
        return identifier

    failures = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(one, device): device for device in identifiers}
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as error:
                failures[futures[future]] = str(error)
    dump(root / "reports/source-fetch.json", {"devices": len(identifiers), "failures": failures})
    if failures:
        raise RuntimeError(f"Source fetch failed for {len(failures)} devices; retry to resume")


def build(root):
    database = root / "catalog.sqlite"
    temporary = root / "catalog.tmp.sqlite"
    temporary.unlink(missing_ok=True)
    db = sqlite3.connect(temporary)
    db.executescript("""
        PRAGMA foreign_keys=ON;
        CREATE TABLE device(id TEXT PRIMARY KEY, metadata TEXT NOT NULL);
        CREATE TABLE release(id TEXT PRIMARY KEY, version TEXT, build TEXT, released TEXT, rsr INTEGER);
        CREATE TABLE target(release_id TEXT REFERENCES release, device TEXT REFERENCES device,
            PRIMARY KEY(release_id,device));
        CREATE TABLE asset(id TEXT PRIMARY KEY, kind TEXT, url TEXT UNIQUE, size INTEGER, hashes TEXT);
        CREATE TABLE delivery(id TEXT PRIMARY KEY, asset TEXT REFERENCES asset,
            release_id TEXT REFERENCES release, device TEXT REFERENCES device,
            boards TEXT, prerequisites TEXT, active INTEGER, provider TEXT, source TEXT);
        CREATE INDEX delivery_target ON delivery(release_id,device);
        CREATE INDEX delivery_asset ON delivery(asset);
        CREATE TABLE provenance(path TEXT PRIMARY KEY, sha256 TEXT NOT NULL);
    """)
    excluded = collections.Counter()
    appledb = root / "sources/appledb"
    all_metadata_devices = set()

    def provenance(path):
        relative = str(path.relative_to(root))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        db.execute("INSERT OR IGNORE INTO provenance VALUES (?,?)", (relative, digest))
        return relative

    def device(identifier, metadata=None):
        if DEVICE.fullmatch(identifier):
            db.execute(
                "INSERT OR IGNORE INTO device VALUES (?,?)",
                (identifier, json.dumps(metadata or {})),
            )

    for path in sorted((appledb / "deviceFiles/iPhone").glob("*.json")):
        record = json.loads(path.read_text())
        identifier = record.get("identifier", path.stem)
        if isinstance(identifier, str) and DEVICE.fullmatch(identifier):
            device(
                identifier, {k: record.get(k) for k in ("name", "soc", "arch", "board", "model")}
            )
            all_metadata_devices.add(identifier)
            provenance(path)

    def release(record):
        identifier = record["build"] + (":rsr" if record.get("rsr") else "")
        db.execute(
            "INSERT OR IGNORE INTO release VALUES (?,?,?,?,?)",
            (
                identifier,
                record["version"],
                record["build"],
                record.get("released"),
                bool(record.get("rsr")),
            ),
        )
        return identifier

    def target(rid, identifier):
        device(identifier)
        db.execute("INSERT OR IGNORE INTO target VALUES (?,?)", (rid, identifier))

    def delivery(record, rid, identifier, provider, source):
        kind = record.get("type", "ipsw")
        if kind not in ("ipsw", "ota"):
            return
        for link in record.get("links", []):
            url = link["url"]
            aid = hashlib.sha256(url.encode()).hexdigest()[:24]
            hashes = {
                k.lower().replace("sha2-256", "sha256"): v.lower()
                for k, v in record.get("hashes", {}).items()
            }
            db.execute(
                "INSERT OR IGNORE INTO asset VALUES (?,?,?,?,?)",
                (aid, kind, url, record.get("size"), json.dumps(hashes, sort_keys=True)),
            )
            # Merge independent sources; mismatched payload checksums must be visible.
            previous = json.loads(
                db.execute("SELECT hashes FROM asset WHERE id=?", (aid,)).fetchone()[0]
            )
            for key, value in hashes.items():
                if key in previous and previous[key] != value:
                    raise ValueError(f"Conflicting {key} checksum for {url}")
            db.execute(
                "UPDATE asset SET hashes=?, size=COALESCE(size,?) WHERE id=?",
                (json.dumps(previous | hashes, sort_keys=True), record.get("size"), aid),
            )
            prerequisite = record.get("prerequisiteBuild", [])
            if isinstance(prerequisite, str):
                prerequisite = [prerequisite]
            row = [
                aid,
                rid,
                identifier,
                json.dumps(record.get("boardMap", []), sort_keys=True),
                json.dumps(prerequisite, sort_keys=True),
                int(link["active"]) if "active" in link else -1,
                provider,
                source,
            ]
            key = hashlib.sha256(json.dumps(row).encode()).hexdigest()
            db.execute("INSERT OR IGNORE INTO delivery VALUES (?,?,?,?,?,?,?,?,?)", [key, *row])

    paths = [
        *(appledb / "osFiles/iOS").rglob("*.json"),
        *(appledb / "osFiles/Rapid Security Responses/iOS").rglob("*.json"),
    ]
    for path in sorted(paths):
        record = json.loads(path.read_text())
        if not in_scope(record):
            excluded["appledb_outside_scope_or_prerelease"] += 1
            continue
        identifiers = [d for d in record.get("deviceMap", []) if DEVICE.fullmatch(d)]
        if not identifiers:
            continue
        source = provenance(path)
        rid = release(record)
        for identifier in identifiers:
            target(rid, identifier)
        for asset in record.get("sources", []):
            for identifier in asset.get("deviceMap", identifiers):
                if DEVICE.fullmatch(identifier):
                    target(rid, identifier)
                    delivery(asset, rid, identifier, "appledb", source)
        # RC/beta duplicate entries deliberately do not leak back into the stable set.
        excluded["appledb_duplicate_entries"] += len(record.get("createDuplicateEntries", []))

    for path in sorted((root / "sources/ipsw-me").glob("iPhone*.json")):
        data = json.loads(path.read_text())
        identifier = data["identifier"]
        all_metadata_devices.add(identifier)
        source = provenance(path)
        for fw in data.get("firmwares", []):
            if not in_scope(fw):
                continue
            rid = release(
                {
                    "version": fw["version"],
                    "build": fw["buildid"],
                    "released": fw.get("releasedate"),
                }
            )
            target(rid, identifier)
            hashes = {k: fw[k + "sum"] for k in ("sha1", "md5", "sha256") if fw.get(k + "sum")}
            delivery(
                {
                    "type": "ipsw",
                    "links": [{"url": fw["url"]}],
                    "size": fw.get("filesize"),
                    "hashes": hashes,
                },
                rid,
                identifier,
                "ipsw.me",
                source,
            )
    commit = subprocess.check_output(
        ["git", "-C", str(appledb), "rev-parse", "HEAD"], text=True
    ).strip()
    db.commit()
    rows = db.execute("""SELECT r.id,r.version,r.build,r.rsr,t.device,
        COUNT(DISTINCT CASE WHEN a.kind='ipsw' THEN a.id END),
        COUNT(DISTINCT CASE WHEN a.kind='ota' THEN a.id END)
        FROM target t JOIN release r ON r.id=t.release_id
        LEFT JOIN delivery d ON d.release_id=t.release_id AND d.device=t.device
        LEFT JOIN asset a ON a.id=d.asset GROUP BY r.id,t.device ORDER BY r.id,t.device""").fetchall()
    used_devices = sorted({r[4] for r in rows})
    discrepancies = db.execute("""SELECT r.version,r.build,t.device,
        GROUP_CONCAT(DISTINCT d.provider) FROM target t JOIN release r ON r.id=t.release_id
        LEFT JOIN delivery d ON d.release_id=t.release_id AND d.device=t.device
        LEFT JOIN asset a ON a.id=d.asset AND a.kind='ipsw'
        WHERE a.kind='ipsw' GROUP BY t.release_id,t.device
        HAVING COUNT(DISTINCT d.provider)<2""").fetchall()
    gaps = [
        {
            "version": r[1],
            "build": r[2],
            "device": r[4],
            "rsr": bool(r[3]),
            "ipsw": r[5],
            "ota": r[6],
        }
        for r in rows
        if not r[5]
    ]
    summary = {
        "schema_version": 1,
        "generated_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": {
            "minimum": "14.0",
            "maximum": "26.0.1",
            "family": "iPhone",
            "stable": True,
            "rsr": True,
            "beta_and_rc": False,
            "release_date_cutoff": None,
        },
        "appledb_commit": commit,
        "device_count": len(used_devices),
        "devices": used_devices,
        "release_builds": db.execute("SELECT COUNT(*) FROM release").fetchone()[0],
        "versions": sorted({r[1] for r in rows}, key=lambda v: (version_key(v), v)),
        "device_build_pairs": len(rows),
        "unique_assets": dict(db.execute("SELECT kind,COUNT(*) FROM asset GROUP BY kind")),
        "ipsw_download_bytes_before_binary_dedup": db.execute(
            "SELECT SUM(size) FROM asset WHERE kind='ipsw'"
        ).fetchone()[0],
        "without_ipsw_pairs": len(gaps),
        "without_any_asset_pairs": sum(not r[5] and not r[6] for r in rows),
        "excluded_counts": dict(excluded),
        "devices_without_in_scope_release": sorted(all_metadata_devices - set(used_devices)),
        "binary_validation": "pending; metadata coverage is not runtime compatibility",
    }
    dump(root / "reports/catalog-summary.json", summary)
    dump(root / "reports/coverage-gaps.json", gaps)
    dump(
        root / "reports/source-discrepancies.json",
        [{"version": v, "build": b, "device": d, "providers": p} for v, b, d, p in discrepancies],
    )
    db.close()
    temporary.replace(database)
    print(
        json.dumps(
            {
                k: summary[k]
                for k in (
                    "device_count",
                    "release_builds",
                    "device_build_pairs",
                    "unique_assets",
                    "without_ipsw_pairs",
                    "without_any_asset_pairs",
                )
            },
            indent=2,
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    if args.fetch:
        sync_ipsw_me(args.root)
    build(args.root)


if __name__ == "__main__":
    main()
