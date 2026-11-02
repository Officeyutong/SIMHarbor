# 固件覆盖研究

[English](README.md) | **简体中文**

主机侧工具索引所有已记录 iPhone 设备标识对应的 **iOS 14.0 至 26.0.1 正式版及快速安全响应版本**。边界按版本号比较，不设发布日期上限。Beta／RC 报告可作为补充证据，不会混入正式版设备／构建目标；此研究范围也不构成 App 的版本／设备门槛。

元数据工作流下载元数据和已有 Markdown 差异报告。下文的按需下载及全版本批处理命令只下载已保存清单明确列出的固件，并固定校验值。数据集、Apple 二进制和分析产物放在公开仓库外。

## 准备来源元数据

在外部选择 `CORPUS` 目录，将 `https://github.com/littlebyteorg/appledb.git` 克隆到 `sources/appledb`，记录提交。稀疏检出需要：

- `deviceFiles/iPhone`
- `osFiles/iOS/18x - 14.x` 至 `osFiles/iOS/23x - 26.x`
- `osFiles/Rapid Security Responses/iOS`

```sh
python3 research/firmware/catalog.py "$CORPUS" --fetch
python3 research/firmware/precomputed.py "$CORPUS"
python3 research/firmware/analyze.py "$CORPUS"
python3 research/firmware/test_catalog.py
```

`--fetch` 用四个 worker 缓存 IPSW.me 设备响应；已有响应会复用，刷新时需显式移除对应缓存。不会自动更新 AppleDB。重建 `catalog.sqlite` 会保留来源校验值及 AppleDB 提交信息。

SQLite 将设备／构建目标、按 URL 去重的资源和来源特定的交付记录分开保存。OTA 前置构建、板型限制及链接活动状态随交付记录保留。缺少可用来源的组合仍是缺口；URL 和公开校验值仅是元数据，不代表已经下载或验证固件。

## 优先复用现成差异报告

`precomputed.py` 固定 `blacktop/ipsw-diffs` 的当前提交，也可通过 `--commit HASH` 指定。它从固定 Git 树枚举范围内的目录，仅抓取相关 CommCenter／驱动 Markdown，找回首页失效链接隐藏的报告。目录标签、报告标题和实际输入文件名分别保留。输出 `reports/PRECOMPUTED_DIFFS.md` 和 `reports/precomputed-diffs.json`，包含输入设备／构建、来源哈希、错误、元数据警告与清单匹配情况。设备／构建逐一绑定到报告 IPSW／OTA 输入文件名；无关示例和输入的交叉组合不能证明覆盖。重复运行同一提交会复用缓存文档。

`analyze.py` 离线读取缓存报告，生成 `RESOLVER_RESEARCH.md`／`resolver-research.json`，记录 APDU、就绪、槽位和生命周期相关变动的原始行号及逐版本缺口。发现只代表调查候选，不是已推导的字段偏移。

报告只适用于实际输入固件，不能推广到同版本全部设备。Beta 标签可能不精确，因此另按真实设备／构建匹配正式版清单。**未列出表示未知，不表示未变化。** 节大小、UUID、符号和字符串可用于筛查，但不能代替指令／控制流图差异，也不能证明私有字段偏移不变。这些采集器都不证明真机兼容。

## 按需下载与静态检查

先在仓库外创建 `reports/targeted-download-plan.json`，包含 `assets` 列表。每项记录清单 ID、版本、构建、设备、精确的 Apple CDN HTTPS URL、大小和公开 SHA256；清单还记录 `total_bytes` 与选择理由。选样是研究决策，不能证明未选固件相同。

```sh
python3 research/firmware/change_points.py "$CORPUS"
python3 research/firmware/download.py "$CORPUS" --plan "$CORPUS/reports/targeted-download-plan.json" --budget-gib 40 --workers 4
python3 research/firmware/extract.py "$CORPUS" --plan "$CORPUS/reports/targeted-download-plan.json" --asset CATALOG_ASSET_ID
python3 research/firmware/macho_inspection.py "$CORPUS" "$CORPUS/artifacts/CATALOG_ASSET_ID"
python3 research/firmware/test_targeted.py
```

下载器使用 aria2，默认四文件并行、每文件八连接，支持续传和 SHA256 校验；不会自动扩大已保存的选样范围。稀疏文件逻辑长度不代表已下载字节数。提取要求已验证的安装包和匹配的 BuildManifest，选择指定板型的 Customer Erase 身份、排除 RecoveryOS，通过只读 APFS FUSE 挂载依次提取 OS／SystemOS，卸载后才删除临时镜像。将固定版本的 `ipsw` 和 `apfs-fuse-build/apfs-fuse` 放入 `$CORPUS/tools`；需要时通过 `ipsw` 解密 AEA，工具版本及来源提交写入研究来源记录。

静态检查使用固定的 ipsw CLI 和 Python Capstone，已验证版本为 5.0.7。记录 UUID、代码哈希、函数边界、选定的解修饰 APDU／就绪签名及局部反汇编。当前检查器要求薄的、小端 64 位 Mach-O；代码哈希包含地址相关指令，哈希变化是二进制差异证据，不证明行为变化。检查器本身不自动发现静态对象字段或跨版本偏移。

识别缺口后，再按需获取镜像、对目标 Mach-O 切片进行哈希去重，并做函数差异或离线 resolver 重放。指令归一化时保留代码访问位移。CommCenter 应与驱动一起比较，真机验证另行进行。

## 文件模型 resolver 重放

`offline_resolver.py` 从薄 Mach-O 还原可读段，在独立内存模型中解码 ARM64e 格式 1／9／12 和普通 64 位格式 2／6 的 chained fixups。`isSimReady` 绑定至提取到的导出地址，其他导入使用镜像外占位地址。通过 `c++filt` 还原 block 标签，并将 block-pointer 修饰符写法归一至既有 CoreSymbolication fixture。未知指针／导入编码明确失败；这是有界分析适配器，不是完整动态链接器或模拟器。

```sh
clang++-22 -std=c++17 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I/usr/lib/python3/dist-packages/capstone/include \
  research/firmware/offline_resolver.cpp tweak/ResolverCore.cpp \
  -l:libcapstone.so.5 -o "$CORPUS/tools/offline-resolver"
python3 research/firmware/offline_resolver.py "$CORPUS/artifacts/ASSET" \
  --output "$CORPUS/replays/ASSET" --runner "$CORPUS/tools/offline-resolver"
python3 research/firmware/test_offline_resolver.py
```

原生 runner 使用项目真实的 ResolverCore，输出部分或完整计划；未解析的计划是分析结果，畸形输入或 runner 崩溃属于错误。17.2.1 文件样本复现 fixture 已知的全部 16 项模块相对位置／字段偏移。校准不证明支持所有编码；主机不会执行目标指令、Registry getter、hook 或活对象探测。

iPhone 12 mini 的 16.5.1（20F75）样本最初暴露内联容器缺口。1.3.22 已通过遍历分析推导出步长 `0x138` 和逻辑字段 `+0x4`。这仍是静态证据，不是真机支持结论。

### 1.3.22 自适应解析重放

六个已收集样本均能推导容器描述符：16.5.1 为内联条目，17.2.1、17.6、18.0、18.6 和 26.0.1 为间接条目。布局不由设备／系统版本选择器提供。后三个样本需要原生打开成功 continuation 路径，26.0.1 还需要一层拆出的辅助函数证据；continuation 目前要求 SIM 就绪。静态成功不验证原生 block 生命周期，也不证明相应设备可管理配置。详见双语 [Patchfinder 文档](../../docs/PATCHFINDER.zh-CN.md)。

安装 Clang 22 和 Capstone 5 头文件／库后，可在仓库根目录运行 `python3 tests/check_sim_container.py`，无需固件捕获。`tests/check_resolver.py` 在私有 fixture 重放后也会运行这些合成遍历测试。

## 完整大版本批处理

`sweep.py --plan` 快照保存清单，选择指定大版本全部不同的 IPSW。没有 IPSW 的目标优先选择完整 OTA；RSR 目标选择一个交付包。没有合适公开来源的目标明确列为缺口；排除 Beta／RC。清单按 URL 去重，不预设不同设备系列等价。

```sh
python3 research/firmware/sweep.py "$CORPUS" --root "$CORPUS/ios16-sweep" --plan --major 16
python3 research/firmware/sweep.py "$CORPUS" --root "$CORPUS/ios16-sweep" --run --workers 4
python3 research/firmware/sweep_report.py "$CORPUS/ios16-sweep" --watch
python3 research/firmware/test_sweep.py
```

不要重新生成正在运行的计划。`--run` 从持久回执续跑，跳过已分析／删除条目。每批最多四文件、aria2 并行下载，保留 100 GiB 空间；失败输入超过 80 GiB 时暂停。每个已验证 IPSW 都按全部相关板型的 Customer Erase 身份关联；仅在 OS 组件与缓存架构一致时共享分析。ARM64 和 ARM64e 分组分别处理，提取器因此支持显式板型／架构及输出目录覆盖。

保留目标 Mach-O、manifest、模块／函数哈希、反汇编和解析结果。临时重放段可复现，重放后删除。提取和静态检查完成后删除输入安装包，包括复用的旧硬链接；提取失败／不完整的输入保留供调查。静态计划未解析是明确的发现，不算兼容通过。`reports/PROGRESS.md` 和 `summary.json` 区分已分析、静态通过、下载失败、OTA 重建不支持及缺少来源。模块集合只按实测 SHA256 分组，代码哈希变化本身不证明语义改变；需重建的 OTA／RSR 不得当作独立完整镜像。

私有研究文档和生成的进度报告默认使用中文；JSON 字段、工具原始诊断及标识保持原样。
