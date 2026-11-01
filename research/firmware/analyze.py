#!/usr/bin/env python3
"""Turn cached diff evidence into a conservative resolver research shortlist."""

import argparse
import collections
import json
from pathlib import Path
import re
import sqlite3

from catalog import dump, version_key

PATTERNS = {
    "apdu_transport": re.compile(
        r"sendSimApdu_(?:start|command|close|block)|sendSimSingleApduCommand_sync"
    ),
    "readiness": re.compile(r"isSimReady|SimState"),
    "slot_or_object_layout": re.compile(
        r"SubscriberSimController|SimInfo|SimDriverInfo|HardwareSimSlot|SimSlot"
    ),
    "registry_or_driver_lifetime": re.compile(
        r"EURSimCommandDriver.*(?:create|C[12]E|D[012]E)|Registry.*getServiceMap|PartialActiveCommandDriver"
    ),
}
SIZE_CHANGE = re.compile(r"^~ (.+?) : (\d+) -> (\d+)$")


def evidence(body):
    """Keep only changed rows, preserving section and line-level source evidence."""
    result = []
    section = "metadata"
    for number, line in enumerate(body.splitlines(), 1):
        if line in ("Symbols:", "Functions:", "CStrings:"):
            section = line[:-1]
            continue
        if not re.match(r"^[+~-]\s", line):
            continue
        categories = [name for name, pattern in PATTERNS.items() if pattern.search(line)]
        if not categories:
            continue
        size = SIZE_CHANGE.fullmatch(line) if section == "Functions" else None
        result.append(
            {
                "line": number,
                "section": section,
                "change": line[0],
                "text": line,
                "categories": categories,
                "function_size": {"symbol": size[1], "old": int(size[2]), "new": int(size[3])}
                if size
                else None,
            }
        )
    return result


def analyze(root):
    source = json.loads((root / "reports/precomputed-diffs.json").read_text())
    db = sqlite3.connect(root / "catalog.sqlite")
    targets = {
        (b, d): v
        for v, b, d in db.execute(
            "SELECT r.version,r.build,t.device FROM target t JOIN release r ON r.id=t.release_id"
        )
    }
    matched = {(m["build"], m["device"]) for p in source["pairs"] for m in p["catalog_matches"]}
    findings = []
    manifest = []
    seen = set()
    for pair in source["pairs"]:
        manifest.append(
            {
                k: pair.get(k)
                for k in (
                    "label",
                    "path",
                    "inputs",
                    "metadata_warnings",
                    "both_inputs_in_stable_iphone_catalog",
                )
            }
        )
        for module, record in pair["modules"].items():
            for detail in record["details"]:
                if detail["path"] in seen:
                    continue
                seen.add(detail["path"])
                body = (root / "sources/ipsw-diffs" / source["commit"] / detail["path"]).read_text()
                changes = evidence(body)
                if not changes:
                    continue
                categories = sorted({c for row in changes for c in row["categories"]})
                findings.append(
                    {
                        "label": pair["label"],
                        "module": module,
                        "path": detail["path"],
                        "url": detail["url"],
                        "sha256": pair["provenance"][detail["path"]],
                        "inputs": pair["inputs"],
                        "both_inputs_in_stable_iphone_catalog": pair[
                            "both_inputs_in_stable_iphone_catalog"
                        ],
                        "categories": categories,
                        "evidence": changes,
                        "interpretation": "Investigation candidate only; symbol renumbering, function-size changes and log strings do not establish ABI or member-layout changes.",
                    }
                )
    priorities = {
        "apdu_transport": 0,
        "readiness": 1,
        "slot_or_object_layout": 2,
        "registry_or_driver_lifetime": 3,
    }
    findings.sort(
        key=lambda f: (min(priorities[c] for c in f["categories"]), f["label"], f["module"])
    )
    versions = []
    for version in sorted(set(targets.values()), key=lambda v: (version_key(v), v)):
        applicable = {key for key, v in targets.items() if v == version}
        observed = applicable & matched
        versions.append(
            {
                "version": version,
                "device_build_targets": len(applicable),
                "targets_seen_in_report_inputs": len(observed),
                "unseen_targets": len(applicable - observed),
                "function_level_binary_validation": "not established",
            }
        )
    summary = {
        "schema_version": 1,
        "upstream_commit": source["commit"],
        "report_pairs": source["pair_count"],
        "failed_pairs": source["fetch_failures"],
        "stable_iphone_input_pairs": source["both_inputs_in_stable_iphone_catalog"],
        "stable_device_build_targets": len(targets),
        "targets_seen_in_report_inputs": len(set(targets) & matched),
        "unseen_targets": len(set(targets) - matched),
        "relevant_module_reports": len(findings),
        "evidence_rows": sum(len(f["evidence"]) for f in findings),
        "category_report_counts": dict(
            collections.Counter(c for f in findings for c in f["categories"])
        ),
        "firmware_downloaded_bytes": 0,
        "function_level_binary_validation": "not established",
        "findings": findings,
        "versions": versions,
        "report_inputs": manifest,
    }
    dump(root / "reports/resolver-research.json", summary)
    lines = [
        "# CommCenter 差异研究结果",
        "",
        "固定上游提交：`" + source["commit"] + "`。本步骤只读取已有文本报告，没有下载固件。",
        "",
        "## 覆盖范围",
        "",
        f"- 固件清单：{len(targets)} 个正式版 iPhone 设备／Build 组合。",
        f"- 现成差异报告：{source['pair_count']} 组，获取失败 {source['fetch_failures']} 组；两端都匹配正式版 iPhone 清单的报告 {source['both_inputs_in_stable_iphone_catalog']} 组。",
        f"- 报告实际输入涉及其中 {len(set(targets) & matched)} 个组合；其余 {len(set(targets) - matched)} 个组合没有输入证据。",
        "- 输入出现仅表示该固件曾用于生成文本报告，不等于已验证二进制、偏移或真机兼容。",
        "",
        "## 对现有 resolver 的影响",
        "",
        "1. APDU 日志字符串在多个版本间出现／消失，因此不能把日志文本当成唯一锚点。",
        "2. APDU 回调符号的 block 编号会变化，应继续使用指令结构和调用关系，避免固定编号。",
        "3. `isSimReady` 的函数长度存在变化，应单独验证状态 getter 与就绪判断的数据流；长度本身不能说明枚举语义如何变化。",
        "4. 驱动构造和 PartialActiveCommandDriver 相关符号变化值得检查对象成员及生命周期，但不是成员偏移变化的直接证据。",
        "5. `Functions: ~ name : old -> new` 是函数长度差异，不是完整指令／控制流图差异。等长函数的指令和字段位移仍可能改变。",
        "6. 目录名、首页标题与实际输入不一致时，以报告记录的完整输入文件名为证据，同时保留不一致警告。",
        "",
        "## 需要优先检查的报告",
        "",
        "以下均为调查候选；不声明 ABI 改动或兼容性结论。Beta 报告仅作为补充证据。",
        "",
    ]
    for finding in findings:
        lines.extend(
            [
                "### " + finding["label"] + " — " + finding["module"],
                "",
                "[原始报告]("
                + finding["url"]
                + ")；类别：`"
                + "`, `".join(finding["categories"])
                + "`。",
                "",
                "记录的输入：" + "; ".join(item["filename"] for item in finding["inputs"]) + "。",
                "",
            ]
        )
        # Keep the human report readable; the JSON retains every changed evidence row.
        for row in finding["evidence"][:6]:
            text = row["text"].replace("|", "\\|")
            if len(text) > 360:
                text = text[:357] + "..."
            lines.append(f"- {row['section']} L{row['line']}: `{text}`")
        if len(finding["evidence"]) > 6:
            lines.append(f"- 其余 {len(finding['evidence']) - 6} 条见 JSON。")
        lines.append("")
    lines.extend(
        [
            "## 各正式版本覆盖",
            "",
            "下表统计输入证据，不是支持列表。",
            "",
            "| iOS | 设备／Build 组合 | 报告输入涉及 | 未涉及 |",
            "|---|---:|---:|---:|",
        ]
    )
    lines.extend(
        f"| {v['version']} | {v['device_build_targets']} | {v['targets_seen_in_report_inputs']} | {v['unseen_targets']} |"
        for v in versions
    )
    lines.extend(
        [
            "",
            "## 后续分析",
            "",
            "优先使用已有本地 17.2.1 样本复现 resolver，再针对缺口获取最少的目标镜像。需要逐函数指令比较或静态字段推导时，现成文本报告无法替代原始二进制。当前不启动批量固件下载。",
            "",
        ]
    )
    (root / "reports/RESOLVER_RESEARCH.md").write_text("\n".join(lines))
    db.close()
    print(
        json.dumps(
            {
                k: v
                for k, v in summary.items()
                if k not in ("findings", "versions", "report_inputs")
            },
            indent=2,
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    analyze(parser.parse_args().root)


if __name__ == "__main__":
    main()
