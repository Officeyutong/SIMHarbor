#!/usr/bin/env python3
"""Bundle only the bilingual user guide; validate repository technical references."""
import argparse
import json
import pathlib
import re
from document_privacy import issues as privacy_issues

ROOT = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = ["en", "zh-Hans"]


def generate(check=False):
    manual = ROOT / "docs/manual"
    index = json.loads((manual / "index.json").read_text())
    ids = [entry["id"] for entry in index]
    assert ids == ["guide"], "The app bundles only its user guide"
    assert len(ids) == len(set(ids))
    outputs = {}
    for language in LANGUAGES:
        pages = []
        for entry in index:
            metadata = entry[language]
            body = (manual / language / (entry["id"] + ".md")).read_text()
            assert metadata["title"] and metadata["summary"] and body.startswith("# ")
            assert not privacy_issues(body), (language, entry["id"], privacy_issues(body))
            assert body.count("```") % 2 == 0, (language, entry["id"], "unclosed code block")
            assert not re.search(r"^```(?!text\s*$|\s*$)", body, re.M), "Use offline text diagrams, not online renderers"
            assert not re.search(r"\[[^\]]+\]\([^)]+\)", body), "Manual reader does not resolve repository links"
            if language == "en":
                assert not re.search(r"[\u4e00-\u9fff]", body), entry["id"]
            pages.append({"id": entry["id"], "title": metadata["title"], "summary": metadata["summary"], "body": body})
        outputs[language] = pages
    # Keep engineering references in both translations aligned with the original route.
    route = (ROOT / "docs/ARCHITECTURE_PORTING.md").read_text()
    offsets = set(re.findall(r"0x[0-9a-f]+", route))
    for language, pages in outputs.items():
        technical = "\n".join((manual / language / (name + ".md")).read_text() for name in ["architecture", "porting"])
        assert set(re.findall(r"0x[0-9a-f]+", technical)) == offsets, (language, "offset mismatch")
        assert "10bdb2fd04e33fcea0a188d064801df2" in technical
        signals = (manual / language / "signals.md").read_text()
        assert "80 E2 91 00 06 BF 3E 03 5C 01 5A" in signals and "BF 3E 03 5C 01 5A" in signals
        path = ROOT / "viewer/Resources" / ("Documentation-" + language + ".json")
        data = (json.dumps(pages, ensure_ascii=False, indent=2) + "\n").encode()
        if check:
            assert path.exists() and path.read_bytes() == data, f"Stale manual: run python3 {__file__}"
        else:
            path.write_bytes(data)
    print("PASS: only the user guide bundled in both languages; repository examples, UUID and offsets match")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    generate(parser.parse_args().check)
