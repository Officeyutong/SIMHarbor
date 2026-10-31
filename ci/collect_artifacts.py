#!/usr/bin/env python3
"""Verify one scheme's real package and collect public release artifacts."""

from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCHEMES = {
    "rootful": ("iphoneos-arm", ""),
    "rootless": ("iphoneos-arm64", "var/jb"),
    "roothide": ("iphoneos-arm64e", ""),
}


def macho_slices(path):
    data = path.read_bytes()
    if data[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", data, 4)[0]
        return [struct.unpack_from(">II", data, 8 + i * 20) for i in range(count)]
    assert data[:4] == b"\xcf\xfa\xed\xfe", "Expected a 64-bit Mach-O binary"
    return [struct.unpack_from("<II", data, 4)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scheme", choices=SCHEMES, default="roothide")
    args = parser.parse_args()
    arch, prefix = SCHEMES[args.scheme]
    version = (ROOT / "VERSION").read_text().strip()
    build = (ROOT / "BUILD_NUMBER").read_text().strip()
    package = ROOT / "packages" / f"com.estk.recon_{version}_{arch}.deb"
    assert package.is_file(), "Expected package missing: " + package.name
    for field, value in [
        ("Version", version),
        ("Architecture", arch),
        ("Package", "com.estk.recon"),
    ]:
        assert (
            subprocess.check_output(["dpkg-deb", "-f", str(package), field], text=True).strip()
            == value
        )
    with tempfile.TemporaryDirectory(prefix="deb-check-") as folder:
        folder = Path(folder)
        subprocess.run(["dpkg-deb", "-x", str(package), str(folder)], check=True)
        subprocess.run(["dpkg-deb", "-e", str(package), str(folder / "DEBIAN")], check=True)
        app = folder / prefix / "Applications/ESTKLog.app"
        assert list(folder.rglob("ESTKLog.app")) == [app], "Incorrect app install prefix"
        tweak = folder / prefix / "Library/MobileSubstrate/DynamicLibraries/estkrecon.dylib"
        assert tweak.is_file()
        substrate = {
            "rootful": b"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "rootless": b"@rpath/CydiaSubstrate.framework/CydiaSubstrate",
            "roothide": b"@loader_path/.jbroot/usr/lib/libsubstrate.dylib",
        }[args.scheme]
        assert substrate in tweak.read_bytes(), "Incorrect substrate dependency install name"
        assert (0x0100000C, 0) in macho_slices(app / "ESTKLog"), "App arm64 slice missing"
        slices = macho_slices(tweak)
        assert (0x0100000C, 0) in slices, "Tweak arm64 slice missing"
        assert (0x0100000C, 0x80000002) in slices, "Versioned arm64e ABI slice missing"
        postinst = (folder / "DEBIAN/postinst").read_text()
        app_path = "/" + (prefix + "/" if prefix else "") + "Applications/ESTKLog.app"
        assert "uicache -p " + app_path in postinst and "@INSTALL_PREFIX@" not in postinst
        info = plistlib.loads((app / "Info.plist").read_bytes())
        assert info["CFBundleShortVersionString"] == version and info["CFBundleVersion"] == build
        for language in ["en", "zh-Hans"]:
            name = "Documentation-" + language + ".json"
            assert (app / name).read_bytes() == (ROOT / "viewer/Resources" / name).read_bytes()
            assert [article["id"] for article in json.loads((app / name).read_text())] == ["guide"]
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    name = f"SIMHarbor_{version}_{args.scheme}.deb"
    shutil.copy2(package, dist / name)
    commit = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()
    (dist / f"build-info_{args.scheme}.json").write_text(
        json.dumps(
            {
                "version": version,
                "build": build,
                "commit": commit,
                "scheme": args.scheme,
                "architecture": arch,
                "dependencies": json.loads((ROOT / "ci/dependencies.json").read_text()),
            },
            indent=2,
        )
        + "\n"
    )
    (dist / f"SHA256SUMS_{args.scheme}.txt").write_text(
        hashlib.sha256((dist / name).read_bytes()).hexdigest() + "  " + name + "\n"
    )
    print("Verified layout, versions, Mach-O ABI and collected " + name)


if __name__ == "__main__":
    main()
