#!/usr/bin/env python3
"""Compare measured resolver layouts and readiness instruction families.

Reports are private Chinese research documents. Normalized instruction identity
is evidence about encoding, not proof of equal semantics or runtime support.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import re

from catalog import dump

FIELDS = (
    "simStorage",
    "simVector",
    "simEntryStride",
    "simPointeeOffset",
    "logicalSlot",
    "encoderChannel",
    "responseSlot",
    "responseChannel",
    "qmiError",
)


def normalize_local_branches(text, address, size):
    """Remove only in-function branch PC placement; keep operands and field offsets."""
    lines = []
    for line in text.splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]+):\s+(\S+)\s*(.*)", line)
        if not match:
            raise ValueError("Malformed saved disassembly")
        offset, mnemonic, operands = match.groups()
        if mnemonic in ("b", "bl", "cbz", "cbnz", "tbz", "tbnz") or mnemonic.startswith("b."):
            target = re.search(r"#0x([0-9a-fA-F]+)$", operands)
            if target and address <= int(target[1], 16) < address + size:
                operands = operands[: target.start()] + f"@+{int(target[1], 16) - address:#x}"
        lines.append(f"{int(offset, 16):04x}: {mnemonic} {operands}".rstrip())
    return "\n".join(lines) + "\n"


def first_return_prefix(text):
    """Retain instructions through the first return; this is not a CFG proof."""
    lines = []
    for line in text.splitlines():
        lines.append(line)
        if re.match(r"^[0-9a-f]+: ret(?:aa|ab)?$", line):
            return "\n".join(lines) + "\n"
    return None


def analyze_results(root, plan=None, state=None):
    plan = plan or json.loads((root / "reports/plan.json").read_text())
    state = state or json.loads((root / "reports/state.json").read_text())
    layouts, readiness, prefixes, failures = {}, {}, {}, collections.Counter()
    versions = {}
    incomplete = []
    samples = []
    excluded = []
    for asset in plan["assets"]:
        version_key = (asset["version"], asset["build"])
        version = versions.setdefault(
            version_key,
            {
                "version": asset["version"],
                "build": asset["build"],
                "planned_targets": set(),
                "analyzed_targets": set(),
                "resolved_targets": set(),
            },
        )
        version["planned_targets"].update(t["device"] for t in asset["targets"])
        entry = state["results"].get(asset["asset"], {})
        if entry.get("status") != "analyzed_deleted":
            continue
        excluded.extend(entry["analysis"].get("excluded_targets", []))
        for index, group in enumerate(entry["analysis"].get("groups", [])):
            targets = {t["device"] for t in group["targets"]}
            version["analyzed_targets"].update(targets)
            if group["resolver"]["status"] == "resolved":
                version["resolved_targets"].update(targets)
            else:
                failures.update(
                    group["resolver"].get("errors", [])
                    or [group["resolver"].get("error", group["resolver"]["status"])]
                )
            folder = root / "artifacts" / asset["asset"] / f"group-{index}"
            result_path = root / "analyses" / asset["asset"] / f"group-{index}/resolver.json"
            inspection_path = folder / "static-inspection.json"
            if not result_path.is_file() or not inspection_path.is_file():
                incomplete.append(
                    {
                        "asset": asset["asset"],
                        "group": index,
                        "reason": "Missing saved resolver/inspection metadata",
                    }
                )
                continue
            result = json.loads(result_path.read_text())
            inspection = json.loads(inspection_path.read_text())
            sample = {
                "asset": asset["asset"],
                "group": index,
                "version": asset["version"],
                "build": asset["build"],
                "arch": group["arch"],
                "devices": sorted(targets),
                "resolver_complete": result["complete"],
                "runner_sha256": result.get("runner_sha256"),
                "modules": group.get("modules", {}),
            }
            if result["complete"]:
                values = {name: result["values"][name] for name in FIELDS}
                key = hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()
                layouts.setdefault(key, {"values": values, "samples": []})["samples"].append(
                    sample.copy()
                )
                sample["layout_family"] = key
            base = inspection["modules"].get("libCommCenterBase.dylib", {})
            for function in base.get("selected_functions", []):
                if "isSimReady(" not in function["symbol"]:
                    continue
                if function["decoded_bytes"] != function["size"]:
                    incomplete.append(
                        {
                            "asset": asset["asset"],
                            "group": index,
                            "reason": "Readiness function was not fully decoded",
                        }
                    )
                    continue
                path = folder / function["disassembly"]
                normalized = normalize_local_branches(
                    path.read_text(), int(function["address"], 16), function["size"]
                )
                key = hashlib.sha256(normalized.encode()).hexdigest()
                readiness.setdefault(
                    key,
                    {
                        "instruction_text": normalized,
                        "function_size": function["size"],
                        "samples": [],
                    },
                )["samples"].append(sample.copy())
                sample["readiness_family"] = key
                prefix = first_return_prefix(normalized)
                if prefix is not None:
                    prefix_key = hashlib.sha256(prefix.encode()).hexdigest()
                    prefixes.setdefault(prefix_key, {"instruction_text": prefix, "samples": []})[
                        "samples"
                    ].append(sample.copy())
                    sample["first_return_prefix_family"] = prefix_key
            samples.append(sample)
    version_rows = []
    for row in versions.values():
        version_rows.append({k: len(v) if isinstance(v, set) else v for k, v in row.items()})
    output = {
        "scope": plan["scope"],
        "sample_groups": len(samples),
        "layouts": layouts,
        "readiness_instruction_families": readiness,
        "readiness_first_return_prefixes": prefixes,
        "unresolved_reasons": dict(failures),
        "versions": version_rows,
        "manifest_exclusions": excluded,
        "incomplete_saved_metadata": incomplete,
        "limitations": [
            "Only saved, analyzed inputs are compared; unprocessed versions remain unknown.",
            "Layout equality does not establish ABI, live-object layout or card communication compatibility.",
            "Only local branch addresses are normalized. All registers, constants, memory displacements and external references are preserved.",
            "Different instruction families do not establish changed predicate semantics or the earliest release containing a change.",
        ],
    }
    dump(root / "reports/ios16-analysis.json", output)
    lines = [
        "# iOS 16 跨版本分析",
        "",
        f"已比较 {len(samples)} 个已保存的镜像组；完整计划中发现 {len(layouts)} 类字段布局、{len(readiness)} 组就绪函数完整编码、{len(prefixes)} 组首个返回指令前缀。",
        "",
        "只比较已完成的实际样本，不把未处理版本认定为相同或已支持。静态通过不等于真机兼容。",
        "",
        "## 已解析的字段布局",
        "",
    ]
    for index, family in enumerate(layouts.values(), 1):
        lines.extend([f"### 布局 {index}", "", "| 字段 | 数值 |", "|---|---|"])
        lines.extend(f"| {name} | {value:#x} |" for name, value in family["values"].items())
        lines.extend(
            [
                "",
                f"样本组数：{len(family['samples'])}；架构：{', '.join(sorted({s['arch'] for s in family['samples']}))}。",
                "",
            ]
        )
    lines.extend(
        [
            "## 就绪函数的指令编码",
            "",
            "只归一化函数内部的分支目标位置；寄存器、常量、字段位移和外部引用均保留。编码不同不能直接解释为就绪语义不同。",
            "",
        ]
    )
    lines.extend(
        [
            "### 首个返回指令前缀",
            "",
            "完整函数的差异可能来自错误处理路径和外部引用地址；这里另列首个 return 之前的指令前缀。前缀相同不是整个控制流图或所有输入语义相同的证明。",
            "",
        ]
    )
    for index, family in enumerate(prefixes.values(), 1):
        lines.extend(
            [
                f"#### 前缀组 {index}",
                "",
                f"样本组数：{len(family['samples'])}。",
                "",
                "```asm",
                family["instruction_text"].rstrip(),
                "```",
                "",
            ]
        )
    lines.extend(
        [
            "### 完整编码分组",
            "",
            "完整的归一化指令和全部样本对应关系保留在 JSON 中。",
            "",
            "| 组 | 字节数 | 样本组数 | 示例版本 | 示例架构 |",
            "|---|---:|---:|---|---|",
        ]
    )
    for index, family in enumerate(readiness.values(), 1):
        example = family["samples"][0]
        lines.append(
            f"| {index} | {family['function_size']} | {len(family['samples'])} | {example['version']} | {example['arch']} |"
        )
    lines.append("")
    lines.extend(
        [
            "## 逐构建设备覆盖",
            "",
            "| iOS | Build | 已计划设备 | 已分析设备 | 静态通过设备 |",
            "|---|---|---:|---:|---:|",
        ]
    )
    lines.extend(
        f"| {r['version']} | {r['build']} | {r['planned_targets']} | {r['analyzed_targets']} | {r['resolved_targets']} |"
        for r in version_rows
    )
    lines.extend(
        [
            "",
            "## 失败与来源缺口",
            "",
            f"manifest 排除关联：{len(excluded)}；缺少已保存分析元数据：{len(incomplete)}。完整标识和证据见 ios16-analysis.json。",
            "",
        ]
    )
    lines.extend(f"- {count} 次：`{reason}`" for reason, count in failures.items())
    lines.extend(
        [
            "",
            "实际驱动指针、硬件槽字段、注入和卡片读写仍需逐设备运行时验证。当前样本不能证明哪个版本首次发生语义变化。",
            "",
        ]
    )
    (root / "reports/IOS16_ANALYSIS.md").write_text("\n".join(lines))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    result = analyze_results(args.root.resolve())
    print(
        json.dumps(
            {
                "samples": result["sample_groups"],
                "layouts": len(result["layouts"]),
                "readiness_families": len(result["readiness_instruction_families"]),
            }
        )
    )


if __name__ == "__main__":
    main()
