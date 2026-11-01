# Firmware coverage research

This host-side research tooling indexes **stable iOS 14.0 through 26.0.1**, including rapid security responses, across every recorded iPhone product identifier. Version bounds are numeric; there is no release-date cutoff. Beta/RC reports may be collected as supplementary evidence, but are not silently added to the stable device/build target set. This does not impose a version/device gate on the app.

The default workflow downloads metadata and existing Markdown diffs, **not IPSW/OTA binaries**. No command in these scripts downloads a firmware archive. Keep datasets, Apple binaries and analysis output outside the public repository.

## Prepare source metadata

Choose an external `CORPUS` directory. Clone `https://github.com/littlebyteorg/appledb.git` there as `sources/appledb`, recording its commit. A sparse checkout needs these directories:

- `deviceFiles/iPhone`
- `osFiles/iOS/18x - 14.x` through `osFiles/iOS/23x - 26.x`
- `osFiles/Rapid Security Responses/iOS`

```sh
python3 research/firmware/catalog.py "$CORPUS" --fetch
python3 research/firmware/precomputed.py "$CORPUS"
python3 research/firmware/analyze.py "$CORPUS"
python3 research/firmware/test_catalog.py
```

`--fetch` caches IPSW.me device responses with four workers. Existing responses are reused; explicitly remove a cached response to refresh it. The AppleDB checkout is not automatically updated. Rebuilding `catalog.sqlite` preserves source checksums and AppleDB commit provenance in the reports.

The SQLite catalog separates device/build targets, URL-deduplicated assets and source-specific delivery records. OTA prerequisite builds, board restrictions and link activity remain attached to deliveries. A device/build without an available source remains a coverage gap. Download URLs and published checksums are metadata, not proof that an archive was downloaded or validated.

## Reuse existing diffs first

`precomputed.py` pins the current `blacktop/ipsw-diffs` commit (or accepts `--commit HASH`), enumerates in-range directories from the pinned Git tree and fetches only their relevant CommCenter/driver Markdown documents. This recovers reports hidden behind broken homepage links; report headings and input filenames remain separate evidence when labels disagree. It emits `reports/PRECOMPUTED_DIFFS.md` and `reports/precomputed-diffs.json`, including actual input devices/builds, source hashes, errors, metadata warnings and catalog matches. Device/build pairs are bound to each firmware filename in the IPSWs/OTAs section; unrelated examples and cross-products of input devices/builds cannot establish coverage. Repeat with the same commit to resume from cached documents.

`analyze.py` reads these cached reports without network access and emits `RESOLVER_RESEARCH.md` / `resolver-research.json`: changed APDU, readiness, slot and lifetime evidence with original line numbers, plus per-version coverage gaps. Its findings are investigation candidates, not inferred field offsets.

A report applies to its named input firmware, not every device on that iOS version. A beta label can be imprecise, so the report separately matches actual input builds/devices against the stable catalog. **Not listed means unknown**, not unchanged. Section sizes, UUIDs, symbols and strings are useful screening evidence; they do not constitute instruction/CFG diffs or prove that private member offsets are unchanged. Neither collector establishes runtime compatibility.

Only after identifying gaps should individual archives/images be acquired, target Mach-O slices hashed/deduplicated, and function-level diffs or offline resolver replays performed. Those stages are not implemented by these collectors. Preserve code-access displacements during instruction normalization. Compare CommCenter with its driver module, and validate on devices separately.

# 固件覆盖研究

工具在主机侧索引 **iOS 14.0 至 26.0.1 的正式版及快速安全响应版本**，覆盖元数据中全部适用的 iPhone 设备标识。边界按版本号比较，不设发布日期上限。Beta／RC 差异报告可作为补充证据，但不会混入正式版设备／Build 目标集合，也不会改变 App 的运行时兼容策略。

默认仅下载元数据和现成 Markdown 报告，**不会下载 IPSW／OTA 固件**。这两个采集脚本均没有固件下载步骤。请将数据集、Apple 二进制和分析产物放在公开仓库外。

按照上面的目录要求准备固定提交的 AppleDB，然后运行四条命令。`catalog.sqlite` 分别保存设备／Build、按 URL 去重的资源及各来源的交付限制；保留 OTA 前置 Build、板型和链接状态。没有来源的组合仍然是缺口，不能算已验证。重复运行会复用缓存；更新来源需显式刷新。

优先阅读 `reports/PRECOMPUTED_DIFFS.md` 和对应 JSON。采集器按固定提交的 Git 目录树发现报告，避免首页错误链接漏项；报告包含原始输入机型／Build、校验值、错误及元数据不一致警告。设备与 Build 按输入文件名逐一绑定，正文中的示例不会被当作输入。`analyze.py` 离线生成 `RESOLVER_RESEARCH.md`／`resolver-research.json`，记录 APDU／就绪／卡槽／生命周期相关变动的原始行号及逐版本缺口。某机型报告不能外推至同版本所有设备；“未列出”表示未知，不能解释为二进制相同。节／UUID／符号／字符串差异可用于筛选，但不能替代指令／控制流图差异或证明成员偏移不变。

待识别出报告缺口后，再按需获取单个镜像、对目标二进制去重、运行函数级差异及静态 resolver 回归；这些步骤尚未包含在当前采集器中。静态通过也不等于真机兼容。
