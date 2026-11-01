#!/usr/bin/env python3
"""Classify reported code changes without equating absence of evidence with identity."""

import argparse
import collections
import json
from pathlib import Path
import re

from catalog import dump
from analyze import evidence


def classify(body):
    sizes = {}
    for sign, size in re.findall(
        r"^([+-])\s+__TEXT\.__text:\s*(0x[0-9a-fA-F]+)", body, re.MULTILINE
    ):
        sizes[sign] = int(size, 16)
    code_size_changed = len(sizes) == 2 and sizes["-"] != sizes["+"]
    changed_functions = [
        {"symbol": name, "old": int(old), "new": int(new)}
        for name, old, new in re.findall(r"^~ (.+?) : (\d+) -> (\d+)$", body, re.MULTILINE)
    ]
    relevant = evidence(body)
    additions, removals = collections.Counter(), collections.Counter()
    for row in relevant:
        if row["section"] == "Symbols" and "apdu_transport" in row["categories"]:
            symbol = re.sub(
                r"(?<=block_invoke)\.\d+$|(?<=block_invoke_2)\.\d+$", "", row["text"][2:]
            )
            if row["change"] == "+":
                additions[symbol] += 1
            if row["change"] == "-":
                removals[symbol] += 1
    positive = code_size_changed or bool(changed_functions)
    return {
        "classification": "reported_code_change"
        if positive
        else "no_code_change_evidence_in_summary",
        "text_size": {"old": sizes.get("-"), "new": sizes.get("+")},
        "changed_functions": changed_functions,
        "apdu_symbol_changes_only_renumbered": bool(additions) and additions == removals,
        "relevant_function_size_changes": [
            r["function_size"] for r in relevant if r["function_size"]
        ],
        "relevant_changed_rows": len(relevant),
        "semantic_or_member_offset_change": "not established by these summaries",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root
    source = json.loads((root / "reports/precomputed-diffs.json").read_text())
    records = []
    for pair in source["pairs"]:
        modules = {}
        for module, info in pair["modules"].items():
            analyses = []
            for detail in info["details"]:
                body = (root / "sources/ipsw-diffs" / source["commit"] / detail["path"]).read_text()
                analyses.append(classify(body) | {"path": detail["path"], "url": detail["url"]})
            modules[module] = analyses
        records.append(
            {
                "comparison": pair["label"],
                "inputs": pair["inputs"],
                "stable_iphone_pair": pair["both_inputs_in_stable_iphone_catalog"],
                "modules": modules,
            }
        )
    plan = json.loads((root / "reports/targeted-download-plan.json").read_text())
    result = {
        "schema_version": 1,
        "upstream_commit": source["commit"],
        "definition": "Reported text-section size or function-size change establishes changed code extent, not necessarily changed semantics or member offsets. Missing reports remain unknown.",
        "report_pairs": records,
        "selected_stable_samples": plan["assets"],
        "selected_bytes": plan["total_bytes"],
        "selection_limitations": "Beta evidence motivates a stable follow-up sample; it does not prove that exact change first appeared in that stable release. Selected devices do not establish equivalence for other devices.",
    }
    dump(root / "reports/change-points.json", result)
    lines = [
        "# CommCenter 变化节点与精简取样清单",
        "",
        "## 判断标准",
        "",
        "- 代码段或函数长度变化：报告支持“代码范围发生变化”，优先分析。",
        "- 符号编号、字符串或 UUID 变化：单独记录，不能据此认定 ABI／字段布局改变。",
        "- 没有报告、没有列出某模块或函数等长：均不能认定二进制相同。",
        "- Beta 证据只用于选择后续正式版样本，不把 Beta 变化发生时间冒充为正式版结论。",
        "",
        "## 本轮只下载以下四个样本",
        "",
        "| 正式版本 | Build | 设备 | 大小 GB | 选择原因 |",
        "|---|---|---|---:|---|",
    ]
    for asset in plan["assets"]:
        lines.append(
            f"| {asset['version']} | {asset['build']} | {asset['device']} | {asset['size'] / 1e9:.2f} | {asset['reason']} |"
        )
    lines.extend(
        [
            "",
            f"总大小 {plan['total_bytes'] / 1e9:.2f} GB；aria2 四文件并行、每文件八个分段连接，完整文件按公开 SHA256 校验。复用已有 17.2.1 样本。",
            "",
            "iOS 14–16 的历史主干以及其他机型仍有证据缺口，本轮不因此下载全部固件，也不声明它们没有变化。",
            "",
            "## 有代码变化证据的比较",
            "",
            "| 比较 | 输入状态 | 模块 | TEXT 变化字节 | 报告函数长度变化数 | 直接相关函数长度变化数 |",
            "|---|---|---|---:|---:|---:|",
        ]
    )
    for record in records:
        for module, analyses in record["modules"].items():
            for item in analyses:
                if item["classification"] != "reported_code_change":
                    continue
                sizes = item["text_size"]
                delta = str(sizes["new"] - sizes["old"]) if None not in sizes.values() else "未列出"
                label = f"[{record['comparison']}]({item['url']})"
                lines.append(
                    f"| {label} | {'正式版 iPhone' if record['stable_iphone_pair'] else '含预发布或未确认输入'} | {module} | {delta} | {len(item['changed_functions'])} | {len(item['relevant_function_size_changes'])} |"
                )
    lines.extend(
        [
            "",
            "列表表示已有报告中的变化证据，不是范围内所有实质变化版本的穷举。需要在取回的正式版二进制上核对 UUID、代码、函数与私有布局，才能进一步判断 resolver 是否需要适配。",
            "",
        ]
    )
    (root / "reports/CHANGE_POINTS.md").write_text("\n".join(lines))
    print("Wrote change-points.json and CHANGE_POINTS.md")


if __name__ == "__main__":
    main()
