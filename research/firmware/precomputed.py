#!/usr/bin/env python3
"""Collect existing textual firmware diffs; never download firmware binaries."""

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import posixpath
import re
import sqlite3
import subprocess
import urllib.error
import urllib.request

from catalog import dump, version_key

REPOSITORY = "https://github.com/blacktop/ipsw-diffs"
RAW = "https://raw.githubusercontent.com/blacktop/ipsw-diffs/"
MODULES = (
    "CommCenter",
    "libCommCenterMCommandDrivers.dylib",
    "libCommCenterKCommandDrivers.dylib",
    "libCommCenterBase.dylib",
)
MAX_DOCUMENT = 16 * 1024 * 1024


def download(root, commit, path):
    # Restrict the collector to Markdown documents in this one upstream repository.
    path = posixpath.normpath(path)
    if path.startswith(("../", "/")) or not path.endswith(".md"):
        raise ValueError("Not an upstream Markdown report: " + path)
    destination = root / "sources/ipsw-diffs" / commit / path
    if destination.exists():
        return destination.read_text()
    request = urllib.request.Request(
        RAW + commit + "/" + path, headers={"User-Agent": "SIMHarbor-firmware-research"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read(MAX_DOCUMENT + 1)
    if len(raw) > MAX_DOCUMENT:
        raise ValueError("Report exceeds collection limit")
    text = raw.decode("utf-8")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.with_suffix(".tmp").write_text(text)
    destination.with_suffix(".tmp").replace(destination)
    return text


def entries(readme):
    result = []
    for match in re.finditer(r"\[([^\]\n]+)\]\((iOS/[^)]+\.md)\)", readme):
        label, path = match.groups()
        versions = re.findall(
            r"(?:^|\.vs\s+)(\d+(?:\.\d+){0,2})(?:\s+(?:beta(?:\s+\d+)?|RC))?\s*\(", label
        )
        if len(versions) != 2 or not all(
            (14, 0, 0) <= version_key(v) <= (26, 0, 1) for v in versions
        ):
            continue
        result.append(
            {
                "label": label,
                "path": path,
                "versions": versions,
                "prerelease_label": bool(re.search(r"\b(?:beta|RC)\b", label, re.IGNORECASE)),
            }
        )
    return result


def collect(root, commit):
    readme = download(root, commit, "README.md")
    pairs = entries(readme)

    def one(pair):
        result = dict(pair, modules={}, errors=[], provenance={})
        try:
            text = download(root, commit, pair["path"])
            result["provenance"][pair["path"]] = hashlib.sha256(text.encode()).hexdigest()
            result["firmware_filenames"] = sorted(
                set(re.findall(r"iPhone[\w,.-]+\.(?:ipsw|zip)", text))
            )
            result["devices"] = sorted(set(re.findall(r"\biPhone\d+,\d+(?=_)", text)))
            # These reflect the actual input names, not guessed coverage of other devices.
            result["builds"] = sorted(
                set(re.findall(r"_(\d+[A-Z]\d+[a-z]?)_(?:Restore|OTA)", text))
            )
            for module in MODULES:
                links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", text)
                candidates = [
                    posixpath.normpath(posixpath.join(posixpath.dirname(pair["path"]), target))
                    for label, target in links
                    if label.rsplit("/", 1)[-1] == module
                    and not target.startswith(("http:", "https:", "#"))
                ]
                inline = bool(
                    re.search(r"^>\s*`[^`]*\/" + re.escape(module) + r"`", text, re.MULTILINE)
                )
                details = []
                for path in sorted(set(candidates)):
                    try:
                        body = download(root, commit, path)
                        result["provenance"][path] = hashlib.sha256(body.encode()).hexdigest()
                        details.append(
                            {
                                "path": path,
                                "url": REPOSITORY + "/blob/" + commit + "/" + path,
                                "bytes": len(body.encode()),
                                "apdu_mentions": sorted(
                                    set(
                                        re.findall(
                                            r"[^\n]*(?:sendSimApdu|SingleApdu|EURSimCommandDriver|isSimReady)[^\n]*",
                                            body,
                                        )
                                    )
                                ),
                            }
                        )
                    except (OSError, ValueError) as error:
                        result["errors"].append({"path": path, "error": str(error)})
                result["modules"][module] = {
                    "status": "listed_changed" if candidates or inline else "not_listed_in_report",
                    "inline": inline,
                    "details": details,
                }
            result["status"] = "fetched_with_errors" if result["errors"] else "fetched"
        except (OSError, ValueError) as error:
            result["status"] = "fetch_failed"
            result["errors"].append({"path": pair["path"], "error": str(error)})
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(one, pairs))
    db = sqlite3.connect(root / "catalog.sqlite")
    catalog_builds = {r[0] for r in db.execute("SELECT build FROM release")}
    for pair in results:
        pair["catalog_matches"] = [
            {"build": build, "device": device}
            for build in pair.get("builds", [])
            for device in pair.get("devices", [])
            if db.execute(
                "SELECT 1 FROM target t JOIN release r ON r.id=t.release_id WHERE r.build=? AND t.device=?",
                (build, device),
            ).fetchone()
        ]
        pair["both_inputs_in_stable_iphone_catalog"] = (
            len({m["build"] for m in pair["catalog_matches"]}) == 2
        )
    observed = {m["build"] for pair in results for m in pair["catalog_matches"]}
    byte_count = sum(p.stat().st_size for p in (root / "sources/ipsw-diffs" / commit).rglob("*.md"))
    summary = {
        "schema_version": 1,
        "repository": REPOSITORY,
        "commit": commit,
        "pair_count": len(results),
        "both_inputs_in_stable_iphone_catalog": sum(
            r["both_inputs_in_stable_iphone_catalog"] for r in results
        ),
        "supplementary_prerelease_labels": sum(r["prerelease_label"] for r in results),
        "fetch_failures": sum(r["status"] != "fetched" for r in results),
        "downloaded_text_bytes": byte_count,
        "firmware_downloaded_bytes": 0,
        "catalog_builds": len(catalog_builds),
        "builds_observed_as_diff_inputs": len(catalog_builds & observed),
        "builds_not_observed_as_diff_inputs": sorted(catalog_builds - observed),
        "changed_report_counts": {
            m: sum(r["modules"].get(m, {}).get("status") == "listed_changed" for r in results)
            for m in MODULES
        },
        "limitations": [
            "Textual sections/symbols/strings summaries are not function-level instruction or CFG diffs.",
            "A report applies only to its recorded input firmware/device; no cross-device identity is inferred.",
            "Not listed is not proof of an unchanged binary or an unchanged member offset.",
            "Missing reports, failed fetches and unmatched builds remain unknown.",
        ],
        "pairs": results,
    }
    dump(root / "reports/precomputed-diffs.json", summary)
    lines = [
        "# Existing CommCenter firmware diff coverage",
        "",
        "Upstream: " + REPOSITORY,
        "",
        "Pinned commit: `" + commit + "`",
        "",
        "Only Markdown reports were downloaded. No firmware was downloaded by this collector.",
        "",
        "Not listed means unknown, not unchanged. These are textual binary summaries, not function-level assembly/CFG diffs.",
        "",
        "| Comparison | Recorded devices | Both inputs in stable iPhone catalog | CommCenter | M driver |",
        "|---|---|---|---|---|",
    ]
    for pair in results:
        url = REPOSITORY + "/blob/" + commit + "/" + pair["path"]
        values = [
            "listed changed"
            if pair["modules"].get(m, {}).get("status") == "listed_changed"
            else "not listed / unknown"
            for m in MODULES[:2]
        ]
        lines.append(
            "| ["
            + pair["label"]
            + "]("
            + url
            + ") | "
            + ", ".join(pair.get("devices", []))
            + " | "
            + ("yes" if pair["both_inputs_in_stable_iphone_catalog"] else "no / supplementary")
            + " | "
            + " | ".join(values)
            + " |"
        )
    (root / "reports/PRECOMPUTED_DIFFS.md").write_text("\n".join(lines) + "\n")
    print(
        json.dumps(
            {
                k: v
                for k, v in summary.items()
                if k not in ("pairs", "builds_not_observed_as_diff_inputs")
            },
            indent=2,
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--commit", help="Reuse a known immutable upstream commit")
    args = parser.parse_args()
    commit = (
        args.commit
        or subprocess.check_output(
            ["git", "ls-remote", REPOSITORY + ".git", "refs/heads/main"], text=True
        ).split()[0]
    )
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        parser.error("Expected a full upstream commit hash")
    collect(args.root, commit)


if __name__ == "__main__":
    main()
