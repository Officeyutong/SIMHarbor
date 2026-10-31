#!/usr/bin/env python3
"""Release only a default-branch push whose final VERSION differs from before."""

from pathlib import Path
import argparse, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")


def policy(repo, event, event_name, ref):
    version = (repo / "VERSION").read_text().strip()
    if not SEMVER.fullmatch(version):
        raise ValueError("Invalid project VERSION")
    result = {
        "version": version,
        "should_release": False,
        "reason": "not a default-branch push",
        "previous_version": None,
    }
    branch = event.get("repository", {}).get("default_branch", "main")
    if event_name != "push" or ref != "refs/heads/" + branch or event.get("deleted"):
        return result
    before = event.get("before", "")
    if before and not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", before):
        raise ValueError("Invalid push baseline")
    if not before:
        result["reason"] = "missing push baseline; publication disabled"
        return result
    if set(before) == {"0"}:
        result.update(
            should_release=True, reason="VERSION introduced on initial default-branch push"
        )
        return result
    exists = subprocess.run(
        ["git", "-C", str(repo), "cat-file", "-e", before + "^{commit}"], capture_output=True
    )
    if exists.returncode:
        # Public repos can fetch the old force-push tip by SHA. If it is unavailable,
        # fail closed for publishing while retaining the normal build/artifact.
        try:
            subprocess.run(
                ["git", "-C", str(repo), "fetch", "--no-tags", "--depth=1", "origin", before],
                capture_output=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            result["reason"] = "baseline fetch timed out; publication disabled"
            return result
        exists = subprocess.run(
            ["git", "-C", str(repo), "cat-file", "-e", before + "^{commit}"], capture_output=True
        )
        if exists.returncode:
            result["reason"] = "baseline unavailable; publication disabled"
            return result
    old = subprocess.run(
        ["git", "-C", str(repo), "show", before + ":VERSION"], capture_output=True, text=True
    )
    previous = old.stdout.strip() if old.returncode == 0 else None
    if (
        old.returncode
        and subprocess.run(
            ["git", "-C", str(repo), "ls-tree", before, "VERSION"], capture_output=True, text=True
        ).stdout.strip()
    ):
        result["reason"] = "could not read baseline VERSION; publication disabled"
        return result
    result.update(
        previous_version=previous,
        should_release=version != previous,
        reason="VERSION changed" if version != previous else "VERSION unchanged",
    )
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--report", type=Path)
    p.add_argument("--github-output", type=Path)
    args = p.parse_args()
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    event = json.loads(Path(event_path).read_text()) if event_path else {}
    try:
        result = policy(
            ROOT,
            event,
            os.environ.get("GITHUB_EVENT_NAME", "workflow_dispatch"),
            os.environ.get("GITHUB_REF", ""),
        )
    except (ValueError, OSError) as error:
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps({"error": str(error)}) + "\n")
        raise
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    if args.github_output:
        with args.github_output.open("a") as f:
            f.write(
                "version="
                + result["version"]
                + "\nshould_release="
                + str(result["should_release"]).lower()
                + "\n"
            )
    print(json.dumps(result))


if __name__ == "__main__":
    main()
