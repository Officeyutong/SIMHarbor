#!/usr/bin/env python3
"""Exercise upstream tar naming and reject ambiguous or unsafe devkit entries."""

import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "fetch_gum", Path(__file__).resolve().parents[1] / "scripts/fetch_gum.py"
)
gum = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gum)


class DevkitExtraction(unittest.TestCase):
    def extract(self, names):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode="w") as archive:
                for name, link in names:
                    member = tarfile.TarInfo(name)
                    if link:
                        member.type = tarfile.SYMTYPE
                        member.linkname = "/outside"
                        archive.addfile(member)
                    else:
                        member.size = 3
                        archive.addfile(member, io.BytesIO(b"gum"))
            stream.seek(0)
            with tarfile.open(fileobj=stream, mode="r") as archive:
                gum.extract_devkit(archive, target)
            self.assertEqual((target / "libfrida-gum.a").read_bytes(), b"gum")
            self.assertEqual((target / "frida-gum.h").read_bytes(), b"gum")

    def test_official_dot_prefix_and_plain_names(self):
        for prefix in ["./", ""]:
            with self.subTest(prefix=prefix):
                self.extract([(prefix + "libfrida-gum.a", False), (prefix + "frida-gum.h", False)])

    def test_missing_duplicate_traversal_and_symlink(self):
        for entries in [
            [],
            [("libfrida-gum.a", False), ("./libfrida-gum.a", False)],
            [("../libfrida-gum.a", False)],
            [("libfrida-gum.a", True)],
        ]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.extract(entries)


if __name__ == "__main__":
    unittest.main()
