#!/usr/bin/env python3
"""Summarize durable sweep receipts; analysis success is not device compatibility."""

import argparse
import collections
import json
from pathlib import Path
import time

from catalog import dump


def report(root):
    plan = json.loads((root / "reports/plan.json").read_text())
    state_path = root / "reports/state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {"results": {}}
    records = []
    covered = set()
    resolved = set()
    fingerprints = collections.defaultdict(list)
    for asset in plan["assets"]:
        entry = state["results"].get(asset["asset"], {})
        row = {
            "asset": asset["asset"],
            "version": asset["version"],
            "build": asset["build"],
            "kind": asset["kind"],
            "devices": sorted({t["device"] for t in asset["targets"]}),
            "status": entry.get("status", "pending"),
            "bytes": asset["size"],
            "error": entry.get("error"),
            "groups": [],
        }
        result = entry.get("analysis", {})
        for index, group in enumerate(result.get("groups", [])):
            resolver = group.get("resolver", {})
            keys = [(t["release_id"], t["device"]) for t in group["targets"]]
            if entry.get("status") == "analyzed_deleted":
                covered.update(keys)
                if resolver.get("status") == "resolved":
                    resolved.update(keys)
            fingerprint = tuple(
                (name, info["sha256"]) for name, info in sorted(group.get("modules", {}).items())
            )
            if fingerprint:
                fingerprints[fingerprint].append(
                    {
                        "asset": asset["asset"],
                        "group": index,
                        "version": asset["version"],
                        "build": asset["build"],
                        "devices": sorted({t["device"] for t in group["targets"]}),
                    }
                )
            row["groups"].append(
                {"arch": group["arch"], "board": group["board"], "resolver": resolver}
            )
        if asset["kind"] == "ota" and entry.get("status") == "analyzed_deleted":
            keys = {(t["release_id"], t["device"]) for t in asset["targets"]}
            covered.update(keys)
            if result.get("resolver", {}).get("status") == "resolved":
                resolved.update(keys)
        records.append(row)
    summary = {
        "scope": plan["scope"],
        "planned_assets": len(records),
        "planned_bytes": plan["total_bytes"],
        "asset_statuses": dict(collections.Counter(r["status"] for r in records)),
        "analyzed_device_build_targets": len(covered),
        "static_resolved_device_build_targets": len(resolved),
        "distinct_module_sets": len(fingerprints),
        "analyzed_archive_bytes_deleted": sum(
            r["bytes"] for r in records if r["status"] == "analyzed_deleted"
        ),
        "source_gaps": plan["gaps"],
        "records": records,
        "equivalent_module_sets": [
            {"modules": dict(k), "inputs": v} for k, v in fingerprints.items()
        ],
        "limitations": [
            "Counts require stored analysis and archive deletion receipts. Static resolution is not device verification.",
            "Every archive/device is accounted for; identical binary sets are grouped only by measured file SHA256.",
            "Source gaps and unsupported OTA/delta or file-model encodings remain explicit.",
        ],
    }
    dump(root / "reports/summary.json", summary)
    lines = [
        "# iOS 16 全设备固件分析进度",
        "",
        f"目标：{plan['scope']['devices']} 个设备标识、{plan['scope']['builds']} 个构建、{plan['scope']['targets']} 个设备／构建组合。",
        f"下载清单：{len(records)} 个文件，共 {plan['total_bytes'] / 1e12:.3f} TB；不包括 Beta／RC。",
        f"状态：{summary['asset_statuses']}。",
        f"已分析设备／构建组合：{len(covered)}；其中静态解析通过：{len(resolved)}。",
        f"已分析后删除安装包：{summary['analyzed_archive_bytes_deleted'] / 1e9:.2f} GB。",
        "",
        "静态解析通过不表示真机兼容。提取的目标二进制与分析报告保留，IPSW／OTA 在完成分析后删除。",
        "",
        f"元数据中没有可用完整来源的组合：{len(plan['gaps'])}，详见 summary.json；不计入已覆盖。",
        "",
        "| 版本 | Build | 设备 | 类型 | 状态 | 解析结果／错误 |",
        "|---|---|---|---|---|---|",
    ]
    for row in records:
        if row["status"] == "pending":
            continue
        detail = row["error"] or "; ".join(
            g["resolver"]["status"] + ": " + ", ".join(g["resolver"].get("errors", []))
            for g in row["groups"]
        )
        lines.append(
            f"| {row['version']} | {row['build']} | {', '.join(row['devices'])} | {row['kind']} | {row['status']} | {detail.replace('|', '/').replace(chr(10), ' ')} |"
        )
    (root / "reports/PROGRESS.md").write_text("\n".join(lines) + "\n")
    return {
        k: v
        for k, v in summary.items()
        if k not in ["records", "equivalent_module_sets", "source_gaps", "limitations"]
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--watch", action="store_true")
    args = parser.parse_args()
    while True:
        print(json.dumps(report(args.root.resolve())), flush=True)
        if not args.watch:
            break
        time.sleep(30)


if __name__ == "__main__":
    main()
