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
PAIR_DIRECTORY = re.compile(
    r"(\d+(?:_\d+){0,2})_(\d+[A-Z]\d+[a-z]?)_+vs_(\d+(?:_\d+){0,2})_(\d+[A-Z]\d+[a-z]?)\Z"
)


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


def firmware_inputs(text):
    """Bind devices to each input's own build, using only the input section."""
    section = re.search(r"^## (?:IPSWs|OTAs)\s*\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    if not section:
        return []
    filenames = sorted(set(re.findall(r"(?:iPhone|iPad|iPod)[\w,.-]+\.(?:ipsw|zip)", section[1])))
    result = []
    for filename in filenames:
        build = re.search(r"_(\d+[A-Z]\d+[a-z]?)_(?:Restore|OTA)", filename)
        if build:
            result.append(
                {
                    "filename": filename,
                    "build": build[1],
                    "devices": sorted(set(re.findall(r"iPhone\d+,\d+", filename))),
                }
            )
    return result


def upstream_tree(root, commit, sha):
    """Read bounded Git metadata at immutable object IDs, never archive contents."""
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Invalid tree object ID")
    path = root / "sources/ipsw-diffs" / commit / ".trees" / (sha + ".json")
    if path.exists():
        result = json.loads(path.read_text())
    else:
        url = "https://api.github.com/repos/blacktop/ipsw-diffs/git/trees/" + sha
        request = urllib.request.Request(url, headers={"User-Agent": "SIMHarbor-firmware-research"})
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read(MAX_DOCUMENT + 1)
        if len(raw) > MAX_DOCUMENT:
            raise ValueError("Git tree exceeds collection limit")
        result = json.loads(raw)
        dump(path, result)
    if result.get("truncated"):
        raise ValueError("Truncated upstream tree cannot establish report coverage")
    return result["tree"]


def discover(root, commit, indexed):
    """Enumerate actual pair directories, preserving broken/ambiguous index evidence."""
    tree = upstream_tree(root, commit, commit)
    ios = next(node for node in tree if node["path"] == "iOS" and node["type"] == "tree")
    pending = [("iOS", ios["sha"])]
    directories = {}
    while pending:
        prefix, sha = pending.pop()
        for node in upstream_tree(root, commit, sha):
            if node["type"] != "tree":
                continue
            path = prefix + "/" + node["path"]
            match = PAIR_DIRECTORY.fullmatch(node["path"])
            if match:
                left, old, right, new = match.groups()
                versions = [left.replace("_", "."), right.replace("_", ".")]
                if all((14, 0, 0) <= version_key(v) <= (26, 0, 1) for v in versions):
                    directories[path] = (versions, [old, new])
            elif re.fullmatch(r"iPhone\d+_\d+", node["path"]):
                pending.append((path, node["sha"]))
    pairs = []
    for directory, (versions, builds) in sorted(directories.items()):
        aliases = [entry for entry in indexed if posixpath.dirname(entry["path"]) == directory]
        label = f"{versions[0]} ({builds[0]}) .vs {versions[1]} ({builds[1]})"
        pairs.append(
            {
                "label": label,
                "path": aliases[0]["path"] if aliases else directory + "/README.md",
                "versions": versions,
                "directory_builds": builds,
                "index_labels": [entry["label"] for entry in aliases],
                "prerelease_label": any(entry["prerelease_label"] for entry in aliases),
            }
        )
    broken = [entry for entry in indexed if posixpath.dirname(entry["path"]) not in directories]
    return pairs, broken


def collect(root, commit, scan_tree=False):
    readme = download(root, commit, "README.md")
    pairs = entries(readme)
    broken = []
    if scan_tree:
        pairs, broken = discover(root, commit, pairs)

    def one(pair):
        result = dict(pair, modules={}, errors=[], provenance={})
        try:
            try:
                text = download(root, commit, result["path"])
            except urllib.error.HTTPError as error:
                if error.code != 404 or not scan_tree or not result["path"].endswith("/README.md"):
                    raise
                result["path"] = posixpath.dirname(result["path"]) + "/TOC.md"
                text = download(root, commit, result["path"])
            headings = re.findall(r"^# ([^\n]+)", text, re.MULTILINE)
            if headings:
                result["label"] = headings[0]
                result["prerelease_label"] = bool(
                    re.search(r"\b(?:beta|RC)\b", headings[0], re.IGNORECASE)
                )
            result["metadata_warnings"] = []
            if any(label != result["label"] for label in result.get("index_labels", [])):
                result["metadata_warnings"].append("Homepage label differs from report heading")
            result["provenance"][result["path"]] = hashlib.sha256(text.encode()).hexdigest()
            result["inputs"] = firmware_inputs(text)
            result["firmware_filenames"] = [item["filename"] for item in result["inputs"]]
            result["devices"] = sorted(
                {device for item in result["inputs"] for device in item["devices"]}
            )
            # These reflect the actual input names, not guessed coverage of other devices.
            result["builds"] = sorted({item["build"] for item in result["inputs"]})
            if result.get("directory_builds") and set(result["directory_builds"]) != set(
                result["builds"]
            ):
                result["metadata_warnings"].append(
                    "Directory builds differ from recorded firmware inputs"
                )
            for module in MODULES:
                links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", text)
                candidates = [
                    posixpath.normpath(posixpath.join(posixpath.dirname(result["path"]), target))
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
            {"build": item["build"], "device": device}
            for item in pair.get("inputs", [])
            for device in item["devices"]
            if db.execute(
                "SELECT 1 FROM target t JOIN release r ON r.id=t.release_id WHERE r.build=? AND t.device=?",
                (item["build"], device),
            ).fetchone()
        ]
        pair["both_inputs_in_stable_iphone_catalog"] = len(pair.get("inputs", [])) == 2 and all(
            item["devices"]
            and all(
                {"build": item["build"], "device": device} in pair["catalog_matches"]
                for device in item["devices"]
            )
            for item in pair.get("inputs", [])
        )
    observed = {m["build"] for pair in results for m in pair["catalog_matches"]}
    db.close()
    byte_count = sum(p.stat().st_size for p in (root / "sources/ipsw-diffs" / commit).rglob("*.md"))
    summary = {
        "schema_version": 1,
        "repository": REPOSITORY,
        "commit": commit,
        "pair_count": len(results),
        "discovery": "pinned_git_tree" if scan_tree else "homepage_links_only",
        "broken_homepage_links": broken,
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
    collect(args.root, commit, scan_tree=True)


if __name__ == "__main__":
    main()
