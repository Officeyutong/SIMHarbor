#!/usr/bin/env python3
"""Check current Markdown and generated manuals without retaining private values."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from document_privacy import issues

paths = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md")),
         *sorted((ROOT / "viewer/Resources").glob("Documentation-*.json"))]
failed = []
for path in paths:
    for problem in issues(path.read_text()):
        failed.append(f"{path.relative_to(ROOT)}: {problem}")
assert not failed, "\n".join(failed)
print(f"PASS: {len(paths)} current documentation files; no private addresses, subscriber identifiers, actual operator attribution or activation credentials")
