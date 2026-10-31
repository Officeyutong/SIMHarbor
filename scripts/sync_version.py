#!/usr/bin/env python3
"""Render package and app metadata from the two explicit version files."""

from pathlib import Path
import argparse, re

ROOT = Path(__file__).resolve().parents[1]


def read_versions():
    version = (ROOT / "VERSION").read_text().strip()
    build = (ROOT / "BUILD_NUMBER").read_text().strip()
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("VERSION must be a three-component numeric version")
    if not re.fullmatch(r"[1-9]\d{0,8}", build):
        raise ValueError("BUILD_NUMBER must be a positive integer with at most nine digits")
    return version, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    version, build = read_versions()
    for source, target in [
        ("packaging/control.in", "control"),
        ("packaging/Info.plist.in", "viewer/Resources/Info.plist"),
    ]:
        data = (
            (ROOT / source)
            .read_text()
            .replace("@VERSION@", version)
            .replace("@BUILD_NUMBER@", build)
        )
        path = ROOT / target
        if args.check:
            if not path.exists() or path.read_text() != data:
                raise SystemExit("Stale generated version metadata: " + target)
        else:
            path.write_text(data)
    print("Version metadata OK: " + version + " (" + build + ")")


if __name__ == "__main__":
    main()
