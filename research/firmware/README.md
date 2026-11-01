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

## Targeted acquisition and static inspection

Create an explicit `reports/targeted-download-plan.json` outside the repository, with an `assets` list. Each asset records its catalog ID, version, build, device, exact Apple CDN HTTPS URL, byte size and published SHA256. The plan also records `total_bytes` and selection reasons. Selection is a research sampling decision, not proof that unselected firmware is identical.

```sh
python3 research/firmware/change_points.py "$CORPUS"
python3 research/firmware/download.py "$CORPUS" --plan "$CORPUS/reports/targeted-download-plan.json" --budget-gib 40 --workers 4
python3 research/firmware/extract.py "$CORPUS" --plan "$CORPUS/reports/targeted-download-plan.json" --asset CATALOG_ASSET_ID
python3 research/firmware/macho_inspection.py "$CORPUS" "$CORPUS/artifacts/CATALOG_ASSET_ID"
python3 research/firmware/test_targeted.py
```

The downloader uses aria2, four files in parallel by default and eight connections per file, with resumption and SHA256 validation. It never expands the saved selection from the full catalog. Sparse partial-file length is not treated as downloaded byte count. Extraction requires a verified archive and matching BuildManifest, selects one board-specific customer erase identity (excluding RecoveryOS), uses read-only APFS FUSE mounts, extracts OS/SystemOS components sequentially, and unmounts before removing temporary images. Put pinned `ipsw` and `apfs-fuse-build/apfs-fuse` tools under `$CORPUS/tools`; AEA images are decrypted through `ipsw` when necessary. Keep tool versions and source commits in corpus provenance.

Static inspection uses the pinned ipsw CLI and Python Capstone (validated with 5.0.7). It records UUIDs, code hashes, function starts, selected demangled APDU/readiness signatures and local disassemblies. The current inspector requires thin little-endian 64-bit Mach-O targets. Code hashes include address-dependent instructions; differences are binary evidence, not proof of different behavior. Static object-field discovery and automatic cross-version offset inference are not implemented by this inspector.

Only after identifying gaps should individual archives/images be acquired, target Mach-O slices hashed/deduplicated, and function-level diffs or offline resolver replays performed. Preserve code-access displacements during instruction normalization. Compare CommCenter with its driver module, and validate on devices separately.


## File-model resolver replay

`offline_resolver.py` reconstructs readable segments from thin Mach-O files and decodes ARM64e chained fixups (formats 1, 9 and 12) into a separate memory model. It binds `isSimReady` to its extracted export; other imports use out-of-image placeholders. It reconstructs block labels with `c++filt` and normalizes the block-pointer qualifier spelling to the established CoreSymbolication fixture. Unsupported pointer/import encodings fail explicitly. This is a bounded analysis adapter, not a complete dynamic linker or an emulator.

```sh
clang++-22 -std=c++17 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I/usr/lib/python3/dist-packages/capstone/include \
  research/firmware/offline_resolver.cpp tweak/ResolverCore.cpp \
  -l:libcapstone.so.5 -o "$CORPUS/tools/offline-resolver"
python3 research/firmware/offline_resolver.py "$CORPUS/artifacts/ASSET" \
  --output "$CORPUS/replays/ASSET" --runner "$CORPUS/tools/offline-resolver"
python3 research/firmware/test_offline_resolver.py
```

The native runner uses the project's actual ResolverCore and emits a partial or complete plan. An unresolved plan is an analysis result, while malformed model input or a crashing runner is an error. The established 17.2.1 file sample reproduces all 16 known fixture discoveries using module-relative addresses/field offsets. This calibration does not establish that every firmware encoding is supported. No target instructions, Registry getters, hooks or live-object probes execute in the host harness.

The iPhone 12 mini 16.5.1 (20F75) sample reproduces a static failure at SimInfo-container discovery: its worker walks inline objects (observed stride `0x138`, logical field `+0x4`), while the current rule/reader expect shared-pointer entries. Do not fix this by substituting one vector offset: entry representation and traversal must also be inferred and validated. This is a known analysis finding, not a runtime fix or a device-tested support claim.

# 固件覆盖研究

工具在主机侧索引 **iOS 14.0 至 26.0.1 的正式版及快速安全响应版本**，覆盖元数据中全部适用的 iPhone 设备标识。边界按版本号比较，不设发布日期上限。Beta／RC 差异报告可作为补充证据，但不会混入正式版设备／Build 目标集合，也不会改变 App 的运行时兼容策略。

默认仅下载元数据和现成 Markdown 报告，**不会下载 IPSW／OTA 固件**。这两个采集脚本均没有固件下载步骤。请将数据集、Apple 二进制和分析产物放在公开仓库外。

按照上面的目录要求准备固定提交的 AppleDB，然后运行四条命令。`catalog.sqlite` 分别保存设备／Build、按 URL 去重的资源及各来源的交付限制；保留 OTA 前置 Build、板型和链接状态。没有来源的组合仍然是缺口，不能算已验证。重复运行会复用缓存；更新来源需显式刷新。

优先阅读 `reports/PRECOMPUTED_DIFFS.md` 和对应 JSON。采集器按固定提交的 Git 目录树发现报告，避免首页错误链接漏项；报告包含原始输入机型／Build、校验值、错误及元数据不一致警告。设备与 Build 按输入文件名逐一绑定，正文中的示例不会被当作输入。`analyze.py` 离线生成 `RESOLVER_RESEARCH.md`／`resolver-research.json`，记录 APDU／就绪／卡槽／生命周期相关变动的原始行号及逐版本缺口。某机型报告不能外推至同版本所有设备；“未列出”表示未知，不能解释为二进制相同。节／UUID／符号／字符串差异可用于筛选，但不能替代指令／控制流图差异或证明成员偏移不变。

待识别出报告缺口后，再按需获取单个镜像、对目标二进制去重、运行函数级差异及静态 resolver 回归；这些步骤尚未包含在当前采集器中。静态通过也不等于真机兼容。

按需下载流程要求先保存明确的资源清单与 SHA256，再通过 aria2 四文件并行、每文件八连接下载；不会自动扩展至全部固件。提取阶段校验 BuildManifest，以只读方式挂载 APFS，并回收临时镜像。`macho_inspection.py` 生成 UUID、代码哈希、函数边界、APDU／就绪函数签名及反汇编。代码哈希差异不等于行为差异；当前检查器也不自动推导私有成员偏移。

### Adaptive resolver replay (1.3.22)

The six collected samples now resolve with inferred container descriptors: the 16.5.1 sample uses inline entries; 17.2.1, 17.6, 18.0, 18.6 and 26.0.1 use indirect entries. No OS/device selector supplies those layouts. The newer three samples require the native open-success continuation path, and 26.0.1 additionally requires one level of outlined-helper evidence. The continuation path currently requires a ready SIM. Static success does not test native block lifetimes or establish working profile management on those devices. See the bilingual [patchfinder documentation](../../docs/PATCHFINDER.md).

With Clang 22 and Capstone 5 headers/library installed, run `python3 tests/check_sim_container.py` from the repository root for synthetic traversal tests without any firmware captures. `tests/check_resolver.py` also runs them after private fixture replay.
