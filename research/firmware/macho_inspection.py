#!/usr/bin/env python3
"""Inspect extracted Mach-O targets and disassemble selected functions locally."""

import argparse
import bisect
import hashlib
import json
from pathlib import Path
import re
import subprocess

import capstone
from catalog import dump
from download import sha256

SELECTED = re.compile(
    r"subscriber::EURSimCommandDriver::sendSimApdu_(?:start|command|close)\(|subscriber::isSimReady\("
)


def function_starts(path, toc):
    text = next(
        load
        for load in toc["loads"]
        if load.get("load_cmd") == "LC_SEGMENT_64" and load.get("name") == "__TEXT"
    )
    command = next(
        (load for load in toc["loads"] if load.get("load_cmd") == "LC_FUNCTION_STARTS"), None
    )
    if not command:
        return []
    if command["offset"] < 0 or command["size"] > path.stat().st_size - command["offset"]:
        raise ValueError("Invalid function-start data bounds")
    with path.open("rb") as stream:
        stream.seek(command["offset"])
        raw = stream.read(command["size"])
    starts, address, value, shift = [], text["addr"], 0, 0
    for byte in raw:
        value |= (byte & 127) << shift
        if byte & 128:
            shift += 7
            if shift >= 64:
                raise ValueError("Invalid function-start ULEB128")
            continue
        if not value:
            return starts
        address += value
        if address >= text["addr"] + text["memsz"]:
            raise ValueError("Function start outside TEXT segment")
        starts.append(address)
        value = shift = 0
    if shift:
        raise ValueError("Truncated function-start ULEB128")
    return starts


def inspect(root, folder):
    ipsw = (root / "tools/ipsw").resolve()
    report = {
        "folder": str(folder.resolve()),
        "modules": {},
        "limitations": "Raw code hashes and symbol prototypes are static evidence, not proof of private object layout or device compatibility. No code was executed.",
    }
    for path in sorted(folder.iterdir()):
        if not (path.name == "CommCenter" or path.suffix == ".dylib"):
            continue
        with path.open("rb") as stream:
            magic = stream.read(4)
        if magic != b"\xcf\xfa\xed\xfe":
            raise ValueError("Expected a thin little-endian Mach-O: " + path.name)
        toc = json.loads(subprocess.check_output([str(ipsw), "macho", "info", str(path), "--json"]))
        dump(folder / (path.name + ".macho.json"), toc)
        symbols = subprocess.check_output(
            [str(ipsw), "macho", "info", str(path), "--symbols", "--demangle"], text=True
        )
        (folder / (path.name + ".symbols.txt")).write_text(symbols)
        starts = function_starts(path, toc)
        sections = [section for load in toc["loads"] for section in load.get("sections", [])]
        code = next(
            section
            for section in sections
            if section["segment"] == "__TEXT" and section["name"] == "__text"
        )
        with path.open("rb") as stream:
            stream.seek(code["offset"])
            data = stream.read(code["size"])
        if len(data) != code["size"]:
            raise ValueError("Truncated code section")
        module = {
            "sha256": sha256(path),
            "header": toc["header"],
            "uuid": next(
                (load.get("uuid") for load in toc["loads"] if load.get("load_cmd") == "LC_UUID"),
                None,
            ),
            "code_size": len(data),
            "code_sha256": hashlib.sha256(data).hexdigest(),
            "function_start_count": len(starts),
            "selected_functions": [],
        }
        decoder = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)
        for line in symbols.splitlines():
            if not SELECTED.search(line) or "(__TEXT,__text)" not in line:
                continue
            match = re.match(r"^0x([0-9a-fA-F]+):.*?\t(.+?)\s*$", line)
            if not match:
                continue
            address = int(match[1], 16)
            index = bisect.bisect_left(starts, address)
            if index == len(starts) or starts[index] != address:
                raise ValueError("Selected symbol is not at a function boundary")
            end = starts[index + 1] if index + 1 < len(starts) else code["addr"] + code["size"]
            if (
                not (code["addr"] <= address < end <= code["addr"] + code["size"])
                or end - address > 65536
            ):
                raise ValueError("Selected function has invalid code bounds")
            body = data[address - code["addr"] : end - code["addr"]]
            instructions = list(decoder.disasm(body, address))
            stem = re.search(r"(sendSimApdu_(?:start|command|close)|isSimReady)", match[2])[1]
            disassembly = folder / (path.name + "." + stem + ".asm")
            disassembly.write_text(
                "\n".join(
                    f"{i.address - address:04x}: {i.mnemonic} {i.op_str}" for i in instructions
                )
                + "\n"
            )
            module["selected_functions"].append(
                {
                    "symbol": match[2],
                    "address": hex(address),
                    "size": len(body),
                    "sha256": hashlib.sha256(body).hexdigest(),
                    "decoded_bytes": sum(i.size for i in instructions),
                    "disassembly": disassembly.name,
                }
            )
        expected = (
            ("sendSimApdu_start", "sendSimApdu_command", "sendSimApdu_close")
            if path.name == "libCommCenterMCommandDrivers.dylib"
            else ("isSimReady",)
            if path.name == "libCommCenterBase.dylib"
            else ()
        )
        module["selected_symbol_resolution"] = {
            name: any(name + "(" in item["symbol"] for item in module["selected_functions"])
            for name in expected
        }
        module["unresolved_symbol_note"] = (
            "A missing extracted symbol may be stripped, inlined or omitted by extraction; it does not prove the function is absent."
        )
        report["modules"][path.name] = module
    dump(folder / "static-inspection.json", report)
    print("Inspected", folder.name, ", ".join(report["modules"]), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    inspect(args.root.resolve(), args.folder.resolve())


if __name__ == "__main__":
    main()
