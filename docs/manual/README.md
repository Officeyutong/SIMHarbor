# Bilingual user guide and repository technical documentation

**English** | [简体中文](README.zh-CN.md)

The app bundles only the guide listed in `index.json`: `en/guide.md` and `zh-Hans/guide.md`. Its native User Guide tab displays the article directly, supports selection/copying and Dynamic Type, and no longer presents a multi-article directory or search UI. About-page help opens the same guide.

`python3 scripts/build_docs.py` generates `viewer/Resources/Documentation-{en,zh-Hans}.json`, with exactly one guide per language. `build.sh` invokes it automatically. `--check` detects stale resources and is included in offline checks.

Bilingual signals, architecture, porting and validation Markdown remains in the repository and is excluded from app resources. The generator still checks route offsets/UUIDs against both architecture/porting translations and validates the signals guide's Get EID example. The repository patchfinder articles are `docs/PATCHFINDER.md` and `docs/PATCHFINDER.zh-CN.md`; neither is bundled.

The native UITextView reader supports headings, paragraphs, lists, inline code, bold, text code blocks and two-column tables. It does not execute examples or depend on WebKit, JavaScript, a card connection or network access. Firmware reports and open-source licenses remain separate app features.

Documentation records anonymized technical conclusions. Exclude actual device addresses, login credentials, activation codes, card identifiers, personal profile lists and line ownership; use placeholders such as DEVICE_HOST and example.invalid. Public models, OS versions, image UUIDs, instructions, offsets and explicitly public developer information may remain. The generator and `tests/check_docs_privacy.py` check common leaks.
