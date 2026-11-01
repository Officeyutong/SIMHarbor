#!/usr/bin/env python3
"""Linux-only checks. Never connects to or installs anything on an iOS device."""

import json
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def strings(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");', line)
        assert match, (path, line)
        key, value = (json.loads(part) for part in match.groups())
        assert key not in result, (path, "duplicate", key)
        result[key] = value
    return result


def localization():
    resources = ROOT / "viewer/Resources"
    en = strings(resources / "en.lproj/Localizable.strings")
    zh = strings(resources / "zh-Hans.lproj/Localizable.strings")
    assert en.keys() == zh.keys()
    placeholder = re.compile(
        r"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hljztL])?[@diuoxXfFeEgGaAcCsSpn%]"
    )
    for key in en:
        assert en[key] == key
        assert placeholder.findall(key) == placeholder.findall(zh[key]), key
        assert not re.search(r"[\u4e00-\u9fff]", key), key
    for source in (ROOT / "viewer").glob("*.m"):
        for match in re.finditer(r'SHL\(\s*@("(?:\\.|[^"\\])*")\s*\)', source.read_text()):
            key = json.loads(match[1])
            assert key in en, (source.name, key)
    for match in re.finditer(
        r'return\s+("(?:\\.|[^"\\])*")\s*;', (ROOT / "viewer/SignalCodec.c").read_text()
    ):
        assert json.loads(match[1]) in en
    for source in [ROOT / "tweak/Apdu.mm", ROOT / "viewer/LPAEngine.m"]:
        for match in re.finditer(
            r'(?:fail\(|stage:|warn:|failure:)\s*@("(?:\\.|[^"\\])*")', source.read_text()
        ):
            assert json.loads(match[1]) in en, (source.name, match[1])
    for language in ["en", "zh-Hans"]:
        info = strings(resources / (language + ".lproj/InfoPlist.strings"))
        assert {"CFBundleDisplayName", "NSCameraUsageDescription"} <= info.keys()
    print(
        f"PASS: {len(en)} English/Chinese localization keys, format placeholders, console validation messages and permission descriptions"
    )


def native():
    with tempfile.TemporaryDirectory(prefix="simharbor-offline-") as folder:
        slots = pathlib.Path(folder) / "test-slot-routing"
        subprocess.run(
            [
                "clang++-22",
                "-std=c++17",
                "-g",
                "-O1",
                "-fsanitize=address,undefined",
                "-fno-omit-frame-pointer",
                str(ROOT / "tests/test_slot_routing.cpp"),
                "-o",
                str(slots),
            ],
            check=True,
        )
        subprocess.run([str(slots)], check=True)
        binary = pathlib.Path(folder) / "test-signals"
        sources = [ROOT / "tests/test_signals.c", ROOT / "viewer/SignalCodec.c"]
        sources += sorted((ROOT / "vendor/euicc").glob("*.c"))
        sources += [ROOT / "vendor/cjson/cJSON.c", ROOT / "vendor/cjson-ext/cJSON_ex.c"]
        command = [
            "clang-22",
            "-std=gnu11",
            "-g",
            "-O1",
            "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer",
            "-I" + str(ROOT / "viewer"),
            "-I" + str(ROOT / "vendor"),
            *map(str, sources),
            "-lm",
            "-o",
            str(binary),
        ]
        subprocess.run(command, check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    localization()
    subprocess.run(["python3", str(ROOT / "scripts/build_docs.py"), "--check"], check=True)
    subprocess.run(["python3", str(ROOT / "tests/check_docs_privacy.py")], check=True)
    native()
