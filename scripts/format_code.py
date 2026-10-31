#!/usr/bin/env python3
"""Format project-owned native, Python and shell sources; exclude downloaded/vendor code."""

import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    clang = shutil.which("clang-format-22")
    shfmt = shutil.which("shfmt")
    ruff = ["ruff"] if shutil.which("ruff") else ["uv", "tool", "run", "ruff==0.17.3"]
    if not clang or not shfmt or not shutil.which(ruff[0]):
        raise SystemExit("Install clang-format-22, shfmt and ruff (or uv) before formatting.")
    native = sorted(
        p
        for name in ["viewer", "tweak", "shared", "tests"]
        for p in (ROOT / name).iterdir()
        if p.suffix in {".h", ".hpp", ".m", ".mm", ".c", ".cpp", ".xm"}
    )
    changed = []
    for path in native:
        command = [clang, str(path)]
        if path.suffix == ".xm":
            command = [clang, "--assume-filename=" + str(path.with_suffix(".mm"))]
            formatted = subprocess.check_output(command, input=path.read_bytes())
            # clang-format treats Logos' %ctor as a modulo expression.
            formatted = formatted.replace(b"% ctor", b"%ctor")
        else:
            formatted = subprocess.check_output(command)
        if formatted != path.read_bytes():
            changed.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.write_bytes(formatted)
    python = sorted(
        str(p) for name in ["scripts", "ci", "tests"] for p in (ROOT / name).glob("*.py")
    )
    subprocess.run(
        [*ruff, "format", *(["--check"] if args.check else []), *python], check=True, cwd=ROOT
    )
    shell = [
        ROOT / name
        for name in [
            "build.sh",
            "ccwrap.sh",
            "ci/install_linux_deps.sh",
            "packaging/postinst.in",
            "layout/DEBIAN/prerm",
        ]
    ]
    subprocess.run(
        [shfmt, "-i", "4", "-sr", "-d" if args.check else "-w", *map(str, shell)], check=True
    )
    if args.check and changed:
        raise SystemExit("Native formatting differs: " + ", ".join(changed))
    print(
        f"PASS: formatting {len(native)} native, {len(python)} Python and {len(shell)} shell files"
    )


if __name__ == "__main__":
    main()
