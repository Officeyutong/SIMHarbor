#!/usr/bin/env python3
"""Verify early packaging diagnostics for missing or unusable host converters."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "packaging_tools", ROOT / "ci/check_packaging_tools.py"
)
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class PackagingPreflight(unittest.TestCase):
    def test_missing_converter(self):
        with patch.dict(os.environ, {"PATH": ""}):
            with self.assertRaisesRegex(SystemExit, "Install libplist-utils"):
                packaging.check()

    def test_missing_runtime_library(self):
        with tempfile.TemporaryDirectory() as folder:
            converter = Path(folder) / "plistutil"
            converter.write_text(
                "#!/bin/sh\n"
                "echo 'plistutil: error while loading shared libraries: libplist-2.0.so.4: cannot open shared object file' >&2\n"
                "exit 127\n"
            )
            converter.chmod(0o755)
            with patch.dict(os.environ, {"PATH": folder}):
                with self.assertRaises(SystemExit) as failure:
                    packaging.check()
            message = str(failure.exception)
            self.assertIn("exit 127", message)
            self.assertIn("libplist-2.0.so.4", message)
            self.assertIn("Install libplist-utils", message)

    def test_success_exit_without_conversion_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            converter = Path(folder) / "plistutil"
            converter.write_text("#!/bin/sh\nexit 0\n")
            converter.chmod(0o755)
            with patch.dict(os.environ, {"PATH": folder}):
                with self.assertRaisesRegex(AssertionError, "binary plist"):
                    packaging.check()


if __name__ == "__main__":
    unittest.main()
