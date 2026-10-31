#!/usr/bin/env python3
"""Exercise the actual plist converter selected by the build's toolchain PATH."""

from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def check():
    converter = shutil.which("plistutil")
    if not converter:
        raise SystemExit(
            "Missing plistutil. Install libplist-utils using ci/install_linux_deps.sh."
        )
    expected = {"name": "SIMHarbor", "localized": "芯舟", "enabled": True, "build": 1313}
    with tempfile.TemporaryDirectory(prefix="simharbor-plist-") as folder:
        folder = Path(folder)
        source = folder / "Info.plist"
        source.write_bytes(plistlib.dumps(expected))
        strings = folder / "Localizable.strings"
        strings.write_text('"Error details" = "错误详情";\n')
        for path in [source, strings]:
            command = [converter, "-i", str(path), "-f", "bin", "-o", str(path)]
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode:
                raise SystemExit(
                    f"Packaging converter failed ({converter}, exit {result.returncode}).\n"
                    + result.stderr.strip()
                    + "\nInstall libplist-utils with ci/install_linux_deps.sh; "
                    "the bundled plistutil requires the libplist runtime library."
                )
            assert path.read_bytes().startswith(b"bplist00"), (
                "Converter did not produce a binary plist"
            )
        assert plistlib.loads(source.read_bytes()) == expected, (
            "Plist conversion changed its values"
        )
        assert plistlib.loads(strings.read_bytes()) == {"Error details": "错误详情"}
    print("PASS: packaging plistutil runtime, in-place XML/OpenStep conversion and Unicode values")


if __name__ == "__main__":
    check()
