#!/usr/bin/env python3
"""Model file rebases/imports and replay static ResolverCore, without executing ARM code.

Chained pointer layout reference:
https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h
Unresolved imports get out-of-image placeholders. Only isSimReady is bound to a
real exported address; neither these bindings nor PAC stripping model a full dyld.
"""

import argparse
import json
from pathlib import Path
import re
import struct
import subprocess

from catalog import dump
from macho_inspection import function_starts


def segments(data):
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected thin little-endian 64-bit Mach-O")
    count, size = struct.unpack_from("<II", data, 16)
    if count > 1024 or size > len(data) - 32:
        raise ValueError("Invalid load command bounds")
    offset, result = 32, []
    for _ in range(count):
        cmd, length = struct.unpack_from("<II", data, offset)
        if length < 8 or offset + length > 32 + size:
            raise ValueError("Invalid load command")
        if cmd == 0x19:
            name = data[offset + 8 : offset + 24].split(b"\0")[0].decode()
            address, memsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, offset + 24)
            protection, nsects = struct.unpack_from("<iI", data, offset + 60)
            if 72 + nsects * 80 > length:
                raise ValueError("Invalid section count")
            code = []
            for i in range(nsects):
                section = offset + 72 + i * 80
                start, n = struct.unpack_from("<QQ", data, section + 32)
                flags = struct.unpack_from("<I", data, section + 64)[0]
                if flags & 0x80000400:
                    code.append({"address": start, "size": n, "code": True})
            result.append(
                {
                    "name": name,
                    "address": address,
                    "size": memsize,
                    "fileoff": fileoff,
                    "filesize": filesize,
                    "readable": bool(protection & 1),
                    "sections": code,
                }
            )
        offset += length
    return result


def arm64e_pointer(raw, fmt, base):
    if fmt not in (1, 9, 12):
        raise ValueError("Unsupported chained pointer format " + str(fmt))
    next_delta = ((raw >> 51) & 0x7FF) * 8
    auth = raw >> 63
    binding = (raw >> 62) & 1
    if binding:
        ordinal = raw & ((1 << (24 if fmt == 12 else 16)) - 1)
        addend = 0 if auth else ((raw >> 32) & 0x7FFFF)
        if addend & 0x40000:
            addend -= 0x80000
        return next_delta, None, ordinal, addend
    if auth:
        target = base + (raw & 0xFFFFFFFF)
    else:
        target = raw & ((1 << 43) - 1)
        if fmt in (9, 12):
            target += base
        target |= ((raw >> 43) & 255) << 56
    return next_delta, target, None, 0


def patch_chains(data, toc, memory, base, ready):
    command = next((x for x in toc["loads"] if x.get("load_cmd") == "LC_DYLD_CHAINED_FIXUPS"), None)
    if not command:
        return {"rebases": 0, "bindings": 0, "formats": []}
    blob = data[command["offset"] : command["offset"] + command["size"]]
    version, start, imports, strings, count, kind, compression = struct.unpack_from("<7I", blob)
    if version or compression or kind not in (1, 2, 3):
        raise ValueError("Unsupported chained-fixup header/import encoding")
    entries = []
    for i in range(count):
        if kind == 3:
            word, addend = struct.unpack_from("<Qq", blob, imports + i * 16)
            nameoff = word >> 32
        else:
            word = struct.unpack_from("<I", blob, imports + i * (4 if kind == 1 else 8))[0]
            nameoff = word >> 9
            addend = struct.unpack_from("<i", blob, imports + i * 8 + 4)[0] if kind == 2 else 0
        end = blob.find(b"\0", strings + nameoff)
        if end < 0:
            raise ValueError("Unterminated import name")
        entries.append((blob[strings + nameoff : end].decode(), addend))
    segcount = struct.unpack_from("<I", blob, start)[0]
    stats = {"rebases": 0, "bindings": 0, "formats": set()}
    for i in range(segcount):
        relative = struct.unpack_from("<I", blob, start + 4 + i * 4)[0]
        if not relative:
            continue
        info = start + relative
        length, page, fmt, segoff, _, pages = struct.unpack_from("<IHHQIH", blob, info)
        if (
            fmt not in (1, 9, 12)
            or page not in (4096, 16384)
            or info + length > len(blob)
            or length < 22 + pages * 2
        ):
            raise ValueError("Unsupported/invalid chained segment")
        stats["formats"].add(fmt)
        for j in range(pages):
            first = struct.unpack_from("<H", blob, info + 22 + j * 2)[0]
            if first == 0xFFFF:
                continue
            if first & 0x8000:
                raise ValueError("Multiple chains per page are not modeled")
            address = base + segoff + j * page + first
            end = base + segoff + (j + 1) * page
            while True:
                region = next(
                    (
                        r
                        for r in memory
                        if r["address"] <= address and address + 8 <= r["address"] + len(r["data"])
                    ),
                    None,
                )
                if region is None or address + 8 > end:
                    raise ValueError("Fixup points outside modeled segment/page")
                off = address - region["address"]
                raw = struct.unpack_from("<Q", region["data"], off)[0]
                delta, target, ordinal, addend = arm64e_pointer(raw, fmt, base)
                if ordinal is not None:
                    name, extra = entries[ordinal]
                    target = (
                        (
                            ready
                            if "isSimReady" in name and "isSimReadyOr" not in name
                            else 0x600000000000 + ordinal * 8
                        )
                        + extra
                        + addend
                    )
                    stats["bindings"] += 1
                else:
                    stats["rebases"] += 1
                # dyld applies addends with pointer-width unsigned arithmetic;
                # unrelated imports may also carry high-bit tagging addends.
                struct.pack_into("<Q", region["data"], off, target & ((1 << 64) - 1))
                if not delta:
                    break
                address += delta
    stats["formats"] = sorted(stats["formats"])
    return stats


def prepare(folder, output):
    inspection = json.loads((folder / "static-inspection.json").read_text())
    ready = next(
        int(f["address"], 16)
        for f in inspection["modules"]["libCommCenterBase.dylib"]["selected_functions"]
        if "isSimReady(" in f["symbol"]
    )
    result = {
        "ready": ready,
        "regions": [],
        "symbols": [],
        "model": "Decoded ARM64e chained fixups; isSimReady bound; other imports are non-executable placeholders. Does not model live objects, Registry capture or hooking.",
    }
    all_memory = []
    for key, name in [("cc", "CommCenter"), ("driver", "libCommCenterMCommandDrivers.dylib")]:
        path = folder / name
        data = path.read_bytes()
        toc = json.loads((folder / (name + ".macho.json")).read_text())
        segs = segments(data)
        base = next(s["address"] for s in segs if s["name"] == "__TEXT")
        memory = []
        ranges = []
        for s in segs:
            if s["name"] == "__LINKEDIT" or not s["readable"] or not 0 < s["size"] <= 64 * 1024**2:
                continue
            if s["filesize"] > s["size"] or s["fileoff"] + s["filesize"] > len(data):
                raise ValueError("Invalid segment file bounds")
            region = bytearray(s["size"])
            region[: s["filesize"]] = data[s["fileoff"] : s["fileoff"] + s["filesize"]]
            memory.append({"address": s["address"], "data": region, "name": s["name"]})
            ranges.append({"address": s["address"], "size": s["size"], "code": False})
            ranges.extend(s["sections"])
        stats = patch_chains(data, toc, memory, base, ready)
        result[key] = {
            "name": name,
            "base": base,
            "ranges": ranges,
            "functions": function_starts(path, toc),
            "fixups": stats,
        }
        all_memory.extend((key, r) for r in memory)
    for line in (
        (folder / "libCommCenterMCommandDrivers.dylib.symbols.txt").read_text().splitlines()
    ):
        match = re.match(r"^0x([0-9a-fA-F]+):.*?\t(.+?)\s*$", line)
        if not match or "(__TEXT,__text)" not in line or "sendSimApdu" not in match[2]:
            continue
        name = match[2]
        if "_block_invoke" in name:
            prefix = name[: name.index("_block_invoke")]
            position = prefix.find("_Z")
            if position >= 0:
                name = (
                    "block in "
                    + subprocess.check_output(["c++filt", prefix[position:]], text=True).strip()
                )
        # go-macho and CoreSymbolication place the vendor block_pointer qualifier
        # on different sides of the same function type. Normalize only this spelling.
        name = re.sub(
            r"void\s+block_pointer\((subscriber::HardwareSimSlot,\s*unsigned char)\)",
            r"void (\1) block_pointer",
            name,
        )
        result["symbols"].append({"address": int(match[1], 16), "name": name})
    output.mkdir(parents=True, exist_ok=True)
    for key, region in all_memory:
        path = output / (key + "-" + region["name"] + ".bin")
        path.write_bytes(region["data"])
        result["regions"].append({"address": region["address"], "file": str(path.resolve())})
    dump(output / "input.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runner", type=Path, required=True)
    args = parser.parse_args()
    prepared = prepare(args.folder, args.output)
    result = json.loads(
        subprocess.check_output(
            [str(args.runner.resolve()), str((args.output / "input.json").resolve())], text=True
        )
    )
    result["model"] = prepared["model"]
    result["fixups"] = {k: prepared[k]["fixups"] for k in ("cc", "driver")}
    result["driver_symbol_source"] = (
        "Extracted nlist; block names reconstructed by c++filt, not a runtime CoreSymbolication capture"
    )
    dump(args.output / "result.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
