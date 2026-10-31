#!/usr/bin/env python3
"""Audit files destined for Git; report paths/categories, never matched values."""

from pathlib import Path
import re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
IGNORED = {".git", ".deps", ".theos", "packages", "dist", "__pycache__"}
FORBIDDEN = {"PairingKey.h", "private-research", "device-logs", "releases"}
PATTERNS = {
    "private network endpoint": re.compile(
        r"(?<![\w.])(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![\w.])"
    ),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "access token": re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16})\b"
    ),
    "literal pairing key": re.compile(r'#define\s+SH_PAIRING_KEY\s+@?"[0-9a-fA-F]{32,}"'),
    "literal subscriber identifier": re.compile(r"(?<![\w])(?:89\d{17,30}|\d{32})(?![\w])"),
}
IMAGE_NAMES = {
    "SIMHarbor-1024.png",
    "SIMHarbor-generated-original.png",
    "Icon60@2x.png",
    "Icon60@3x.png",
    "Icon76.png",
    "Icon76@2x.png",
    "Icon83.5@2x.png",
    "QRFixture.png",
}


def paths():
    if (ROOT / ".git").is_dir():
        raw = subprocess.check_output(
            ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        )
        return sorted({ROOT / p.decode() for p in raw.split(b"\0") if p})
    return [
        p
        for p in ROOT.rglob("*")
        if p.is_file()
        and not any(s in IGNORED for s in p.relative_to(ROOT).parts)
        and not ("frida-gum" in p.parts and any(s in {"arm64", "arm64e"} for s in p.parts))
    ]


def main():
    errors = []
    count = 0
    for p in paths():
        rel = p.relative_to(ROOT)
        count += 1
        if any(
            s in FORBIDDEN or s.startswith("research-archive") for s in rel.parts
        ) or p.suffix in {
            ".deb",
            ".ips",
            ".ipsw",
            ".dmg",
            ".device",
            ".pcap",
            ".a",
            ".o",
            ".dylib",
            ".log",
        }:
            errors.append((str(rel), "private data or generated binary"))
            continue
        if p.suffix == ".png":
            if p.name not in IMAGE_NAMES:
                errors.append((str(rel), "unapproved image capture"))
            continue
        if p.is_symlink():
            errors.append((str(rel), "symlink outside source audit"))
            continue
        try:
            data = p.read_text()
        except UnicodeError:
            errors.append((str(rel), "unreviewed binary"))
            continue
        for category, pattern in PATTERNS.items():
            if pattern.search(data):
                errors.append((str(rel), category))
    for path, category in errors:
        print(path + ": " + category, file=sys.stderr)
    if errors:
        raise SystemExit(1)
    print(
        f"PASS: public-source audit ({count} files; no research captures, literal credentials or pairing header)"
    )


if __name__ == "__main__":
    main()
