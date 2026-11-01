#!/usr/bin/env python3
"""Replay private, authorized device fixtures without connecting to an iPhone.

Requires clang-22, clang++-22, Capstone 5 headers/library, a resolver-fixture
folder collected by tools/fr_resolver_fixture.js, and the original unhooked
CommCenter.device next to that folder. Apple binaries are not redistributed.
"""

import argparse
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("fixture", type=pathlib.Path)
parser.add_argument("--capstone-include", default="/usr/lib/python3/dist-packages/capstone/include")
args = parser.parse_args()
assert (args.fixture / "image.json").is_file(), "Missing image metadata"
assert (args.fixture.parent / "CommCenter.device").is_file(), (
    "Missing original, unhooked executable"
)
with tempfile.TemporaryDirectory(prefix="simharbor-resolver-") as folder:
    output = pathlib.Path(folder)
    sanitizer = ["-g", "-O1", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    subprocess.run(
        [
            "clang-22",
            "-std=c11",
            *sanitizer,
            "-c",
            str(ROOT / "vendor/cjson/cJSON.c"),
            "-o",
            str(output / "cjson.o"),
        ],
        check=True,
    )
    subprocess.run(
        [
            "clang++-22",
            "-std=c++17",
            *sanitizer,
            "-I" + args.capstone_include,
            str(ROOT / "tests/test_resolver.cpp"),
            str(ROOT / "tweak/ResolverCore.cpp"),
            str(output / "cjson.o"),
            "-l:libcapstone.so.5",
            "-o",
            str(output / "resolver"),
        ],
        check=True,
    )
    subprocess.run([str(output / "resolver"), str(args.fixture.resolve())], check=True)
    subprocess.run(
        [
            "python3",
            str(ROOT / "tests/check_sim_container.py"),
            "--capstone-include",
            args.capstone_include,
        ],
        check=True,
    )
