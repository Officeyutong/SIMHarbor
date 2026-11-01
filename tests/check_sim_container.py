#!/usr/bin/env python3
"""Run synthetic ARM64 traversal tests on a host with Clang 22 and Capstone 5.

No firmware files, device connection or execution of target instructions is needed.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--capstone-include", default="/usr/lib/python3/dist-packages/capstone/include"
    )
    parser.add_argument("--capstone-library", default="-l:libcapstone.so.5")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="simharbor-containers-") as folder:
        binary = Path(folder) / "containers"
        subprocess.run(
            [
                "clang++-22",
                "-std=c++17",
                "-g",
                "-O1",
                "-fsanitize=address,undefined",
                "-fno-omit-frame-pointer",
                "-I" + args.capstone_include,
                str(ROOT / "tests/test_sim_container.cpp"),
                str(ROOT / "tweak/ResolverCore.cpp"),
                args.capstone_library,
                "-o",
                str(binary),
            ],
            check=True,
        )
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
