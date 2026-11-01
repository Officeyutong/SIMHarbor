# Release notes / 版本记录

## 1.3.20 — build 1320

### English

- Migrate all project-owned runtime JSON to pinned nlohmann/json 3.12.0. Share typed handshake, request/reply payloads, slot/phase and resolver models between app and tweak; replace string-key IPC dispatch/call sites with validated structures. Keep libeuicc's upstream C/cJSON processing unchanged.
- Decode bundled guide articles and operator HTTP status into models; serialize error details, logs and CLI snapshots through the same JSON engine. Compile the affected app sources as Objective-C++ while retaining C linkage at C library/helper boundaries.
- Reject wrong/missing field types, integer overflow, invalid operations, malformed hex, duplicate keys and nesting beyond 64. Preserve wire fields, HMAC and numeric phase values, and align both frame limits at 262,144 bytes including LF. Preserve signed/unsigned integer and boolean Foundation values and Unicode in exports.
- Add shared-schema/framing ASan/UBSan tests, pinned dependency/license checks and a device `--json-check` fixture mode. Existing error-report checks now compare parsed values rather than serializer whitespace. On the roothide phone, JSON/error/notification fixtures, runtime resolver, slot enumeration and read-only card snapshots pass. No download, deletion, profile switch or real operator notification was used in this validation.
- Add bilingual shared-JSON documentation and update IPC documentation and open-source notices.

### 简体中文

- 项目自有运行时 JSON 全部迁移至固定的 nlohmann/json 3.12.0。App/Tweak 共用握手、请求／回复载荷、卡槽／阶段及固件报告结构体，以经校验的类型替代字符串键 IPC 分派和调用；libeuicc 上游 C/cJSON 处理保持不变。
- 内置说明和运营商 HTTP 状态解码为结构体；错误详情、日志及 CLI 快照统一使用同一 JSON 引擎。相关 App 源码改为 Objective-C++，C 库及辅助函数边界保留 C 链接。
- 拒绝字段类型错误／必填项缺失、整数溢出、未知操作、非法十六进制、重复键及超过 64 层的嵌套。保留报文字段、HMAC 和阶段数字编码，将收发帧上限统一为含 LF 的 262,144 字节；导出保留整数／布尔和 Unicode。
- 增加共享 schema／分帧 ASan/UBSan 测试、依赖／许可校验及真机 `--json-check` 模拟入口。错误报告测试改为核对解析后的值，不依赖序列化空格。roothide 真机 JSON／错误／通知模拟、运行时解析、卡槽枚举和只读卡片快照通过；本次没有下载、删除、切换配置或实际向运营商发送通知。
- 增加双语共享 JSON 文档，更新 IPC 文档及开源许可声明。

## 1.3.19 — build 1319

### English

- Default to automatic operator notification submission after successful installation, deletion and profile switching. Add a master switch under Card and settings, retain category switches and existing opt-outs. Merely selecting a slot remains read-only.
- Submit all pending enabled-category notifications on the same EID-bound eUICC in sequence order, including both sides of a profile switch. Remove each notification only after successful submission; stop on the first error, retain pending entries and show a warning while keeping the completed profile operation successful. Preserve other operation warnings.
- Add a device-side `--notification-check` using fixture-only card/network methods for defaults, opt-outs, paired switch events, failure retention and warning preservation. The native fixture checks, offline sanitizer/localization checks and device settings-switch checks pass; no real profile change or operator notification submission was used for this validation. Update the bilingual guide.

### 简体中文

- 安装、删除及切换配置成功后默认自动提交运营商通知。“卡片与设置”新增总开关，保留分类开关及用户原有的关闭设置。仅选择管理卡槽仍为只读。
- 按序号提交同一 EID 绑定 eUICC 上所有已启用类别的待处理通知，包括切换时新配置启用和原配置停用的通知。每条提交成功后才移除，首个错误即停止，保留待处理通知并提示；已完成的卡片操作仍报告成功，其他操作警告也会保留。
- 增加真机 `--notification-check`，使用模拟卡片/网络方法验证默认值、关闭设置、成对切换事件、失败保留及警告保留。原生模拟测试、离线 sanitizer/本地化检查及真机设置开关联动检查通过；本次验证没有实际修改配置或向运营商提交通知。更新双语使用说明。

## 1.3.18 — build 1318

### English

- Make ES10 DER the default signal-console mode. Filling the read-only Get EID example selects DER so STORE DATA and subsequent `61xx` / GET RESPONSE exchanges produce the complete result rather than a raw-mode stop.
- Keep raw APDU batches explicit: do not silently fetch responses or resend commands. Explain `61xx` pending response data and `6Cxx` response-length correction separately from other non-9000 stops. Update the bilingual guide and status-message regression checks.
- Offline sanitizer/localization checks pass. On the roothide phone, raw Get EID returns `6115` with continuation guidance; the example selects DER and returns a complete 21-byte response whose EID matches the card list. These tests only read card data.

### 简体中文

- 自定义信令默认使用 ES10 DER，填入只读 Get EID 示例也会切到此模式，完成 STORE DATA 及后续 `61xx` / GET RESPONSE 交换，返回完整结果，避免示例在原始模式下提前停止。
- 原始 APDU 批次仍按用户输入执行，不静默续取或重发命令；分别解释 `61xx` 后续响应和 `6Cxx` 响应长度修正，与其他非 9000 停止区分。更新双语使用说明及状态消息回归检查。
- 离线 sanitizer/本地化检查通过；roothide 真机验证原始 Get EID 返回 `6115` 并显示续取说明，示例切到 DER 后得到完整 21 字节响应，EID 与卡片列表一致。本次仅进行了只读卡片操作。

## 1.3.17 — build 1317

### English

- Scroll the Profiles page to its header when an operation begins, making the spinner and progress visible even after scrolling down the list. This covers profile deletion, enabling/disabling, renaming, downloading, slot selection and refresh. Respect Reduce Motion; progress updates do not repeatedly force the scroll position.

### 简体中文

- 操作开始时自动把卡片列表滚到页头，让用户能看到转圈和进度提示，覆盖删除、启用/停用、重命名、下载、选择卡槽及刷新。遵循“减弱动态效果”设置；后续进度更新不会反复强制滚动。

## 1.3.16 — build 1316

### English

- Fix overlapping repository addresses on the English and Chinese About page. Developer and repository links now use a vertical title/address layout with explicit self-sizing constraints, full URL wrapping, Dynamic Type and accessible link labels.
- Refresh the English README screenshots after verifying the corrected layout on the phone. Link destinations are unchanged.

### 简体中文

- 修复中英文关于页面仓库地址换行、行高不足及文字重叠。开发者和仓库链接改用上下排列的标题/地址，通过明确约束自动撑高，支持完整地址换行、动态字体和无障碍链接标签。
- 真机核对布局后更新 README 英文截图，链接目标保持不变。

## 1.3.15 — build 1315

### English

- Discover assigned card slots at runtime and add automatic/manual selection. Skip unassigned SimInfo placeholders without dropping valid slots. Auto prefers the remembered EID; an ambiguous new selection requires user choice. A failed explicit selection never falls back to another card.
- Bind LPA engines and profile confirmations to a slot/EID, verify identity at channel opening, serialize all card work, and reject stale activation input. Clear stale profiles and disable download/scan when the selected card cannot be read. Add `slots` IPC and read-only `--slots-check` / `--slot=N` diagnostics.
- Document the findings and routing in English and Chinese. Offline sanitizer/localization checks and all three package builds pass. On the roothide phone after moving the cards, verify explicit reads, slot 1 → slot 2 → Auto UI behavior, unchanged profiles, EID mismatch rejection and activation-input context. No download, deletion or line switch was performed; two simultaneous eUICCs remain untested.

### 简体中文

- 运行时发现已分配卡槽，增加自动/手动选择；跳过未分配的 SimInfo 占位节点而保留有效卡槽。自动模式优先匹配记住的 EID，多个新候选要求用户选择；明确选择失败不会回退到其他卡。
- LPA 实例及卡片操作确认绑定卡槽/EID，打开通道时验证身份，共用串行任务队列，拒绝过期激活码输入。读卡失败清除旧列表并禁用下载/扫码。增加 `slots` IPC、只读 `--slots-check` 和 `--slot=N` 诊断。
- 增加双语研究与实现文档。离线 sanitizer/本地化检查、三种安装包构建通过；交换卡片位置后的 roothide 真机验证逐槽读取、卡槽 1 → 卡槽 2 → 自动界面切换、卡片列表保持不变、EID 不匹配拒绝及激活码输入上下文。本次没有下载、删除或切换线路；尚未实测两张 eUICC 同时在位。

## 1.3.14 — build 1314

### English

- Remove the CommCenter/driver UUID approval table. Device models, iOS build identities and UUIDs no longer decide eligibility; UUIDs remain diagnostic metadata. Attempt discovery on each system and enable transport only after compiled-adapter, complete driver-signature and unique code-plan checks pass. Card operations still require validated live objects and slot mapping.
- Validate Registry exports in their actual owning image rather than requiring CommCenter ownership, support either available getter, verify required hook originals, and report signature checks, hook stage, Registry owner and live-object failure reasons. Allow discovery with 1–16 SimInfo nodes while retaining uniqueness checks.
- Update bilingual Patchfinder/porting/IPC documentation and the firmware report. There is no UUID enrollment step. Runtime checks infer compatibility; matching signatures/layouts do not formally prove every private ABI. Existing ARM64 adapter and iOS 14+ UI API requirements remain implementation boundaries.
- Image replay passes with previously unseen UUIDs and rejects changed callback signatures; existing ASLR, missing/ambiguous/interior-symbol and bounded-object tests pass. Three packages build and pass verification. On the roothide phone, native runtime resolution and a read-only profile-list snapshot pass with the new policy. This does not establish real-device validation of other firmware.

### 简体中文

- 移除 CommCenter/驱动 UUID 批准表。机型、iOS 构建身份和 UUID 不再决定是否启用；UUID 仅作诊断。每个系统都尝试发现，编译适配器、完整驱动签名和唯一代码计划检查通过后启用通道；操作卡片还需要通过活对象和卡槽映射验证。
- Registry 导出按实际所属镜像验证，不再要求属于 CommCenter；支持可用的任一 getter，核对必需 Hook 的原始函数指针，并报告签名、Hook 阶段、Registry 所属镜像和活对象失败原因。接受 1–16 个 SimInfo 节点，同时保留唯一性检查。
- 同步更新双语 Patchfinder、移植、IPC 文档和固件报告，不再需要登记 UUID。运行时检查属于兼容性推断，并非私有 ABI 的形式化证明；ARM64 适配器和 iOS 14+ 界面 API 仍是当前实现边界。
- 镜像回放验证未知 UUID 可以解析、改变回调签名则拒绝；原有 ASLR、符号缺失/歧义/非起点及有界对象测试通过。三种包均构建并通过检查；roothide 真机在新策略下通过原生运行时解析和只读卡片列表快照测试，不代表其他固件已完成真机验证。

## 1.3.13 — build 1313

### English

- Fix the CI packaging failure shared by all three schemes: the bundled `plistutil` could not load `libplist-2.0.so.4`. Install `libplist-utils` and its runtime through the Linux dependency setup.
- Before compiling, exercise the converter selected by the actual build PATH using in-place XML and OpenStep `.strings` conversion. Verify binary plist output and Unicode values. Report missing executables or runtime libraries immediately, including with cached toolchains.
- Add regression tests for a missing converter, the observed loader failure with exit 127, and a converter that reports success without converting. Keep the existing version-gated release and per-push artifact policy.
- Targeted converter checks, regression tests, offline sanitizer/localization checks, release-policy tests and workflow lint pass. All three version 1.3.13 packages build and pass local artifact verification. The hosted workflow has not been rerun with this commit; publishing awaits the user's push.

### 简体中文

- 修复三个方案共同的 CI 打包失败：工具链中的 `plistutil` 无法加载 `libplist-2.0.so.4`。Linux 依赖安装补充 `libplist-utils` 及其运行库。
- 编译前按实际构建 PATH 调用转换器，执行 XML 与 OpenStep `.strings` 原地转换，并核对二进制 plist 和中文内容。转换器缺失或运行库不可用时立即报错，缓存命中时也执行检查。
- 添加转换器不存在、实际遇到的 exit 127 运行库错误，以及伪成功但未转换等回归测试。保留版本号变化才发布、所有 push 上传 artifact 的策略。
- 针对转换器的检查、回归测试、离线 sanitizer/本地化、发布策略测试和工作流语法检查通过；1.3.13 的三种包均在本地构建并通过产物校验。云端工作流尚未运行此提交，等待用户 push 后发布。

## 1.3.12 — build 1312

### English

- Interpret the eUICC installation result instead of displaying a stale HTTP `unknown` message. An existing ICCID (ES10b reason 9) now explains that the profile is already installed and points to the existing profile. Also distinguish insufficient storage, interruption, signature/session/policy failures and selected operator rejections. Unspecified failures are not classified as duplicates.
- Add a bilingual Error details tab. Failed profile operations select it automatically. Show a friendly explanation and copyable diagnostics: failure stage, error domain/code, ES10b result, ES9+ status, HTTP status/request identifier and available failure response, APDU status/response, and underlying network errors. Clear removes the latest error; it is retained in memory across tab and language changes until cleared or the process exits.
- Snapshot diagnostics before cancellation and channel cleanup. Bound captured HTTP failure bodies to 64 KiB and APDU responses to 8 KiB, with truncation indicators. Do not add activation request bodies to this report.
- All three packages build and pass package verification. Offline sanitizer/localization and formatting checks pass. On the roothide phone, `--error-check` passes bilingual fixture tests, snapshot retention and underlying-error reporting; UI fixture replay verifies automatic selection, readable duplicate-install guidance, raw diagnostic retention, copying and clearing. No real duplicate download was repeated for testing.

### 简体中文

- 读取 eUICC 安装结果，避免显示 HTTP 状态中遗留的 `unknown`。ICCID 已存在（ES10b 原因码 9）会提示配置已经安装，应使用现有配置；同时区分空间不足、中断、签名/会话/策略错误及部分运营商拒绝。原因不明时不会误判为重复安装。
- 新增双语「错误详情」页签，配置操作失败后自动切换。展示友好说明及可复制的诊断：失败阶段、错误域/错误码、ES10b 安装结果、ES9+ 状态、HTTP 状态/请求标识和可用的失败响应、APDU 状态/响应及底层网络错误。「清空」移除最近错误；在切换页签或语言时保留，手动清空或进程退出后移除。
- 取消会话和关闭通道前保存诊断快照。HTTP 失败响应最多保留 64 KiB，APDU 响应最多保留 8 KiB，超出时标明截断；不在此报告中加入激活请求正文。
- 三种包均构建并通过包检查，离线 sanitizer/本地化及格式检查通过。roothide 真机 `--error-check` 通过双语样例、快照保留和底层错误测试；界面样例回放验证自动跳转、重复安装说明、原始诊断、复制和清空。测试没有重复下载真实卡片。

## 1.3.11 — build 1311

### English

- Fix live scanning of activation QR codes that image import could recognize but camera metadata did not report. Keep metadata recognition and add Vision recognition directly from camera pixel buffers, sharing the image decoder's request settings and activation-code validation.
- Prefer 1080p capture, align preview and video orientation, and process at most four frames per second on a dedicated serial queue with late-frame dropping. Keep focus controls, prevent auto-lock while scanning, and deliver a recognized code only once to the confirmation dialog.
- Add bilingual recognition hints and English diagnostics for camera setup, first-frame dimensions and recognition source, without logging activation-code payloads.
- All three packages built and passed package validation; formatting and offline sanitizer/localization checks passed. On the roothide phone, logs confirmed 1080 × 1920 camera frames and recognition through Vision; the user confirmed the previously failing QR opened the activation confirmation dialog. This verifies scanning, not a subsequent profile download.

### 简体中文

- 修复图片可以识别、实时摄像头却没有响应的激活二维码问题。保留相机元数据识别，新增直接对相机像素帧执行 Vision 识别，复用图片识别的请求配置和激活码校验。
- 优先采用 1080p 采集，同步预览与视频方向；独立串行队列每秒最多处理四帧并丢弃积压帧。保留对焦操作，扫码期间阻止自动锁屏，识别结果只向确认框交付一次。
- 增加双语识别提示及英文诊断日志，记录相机配置、首帧尺寸与识别来源，不记录激活码内容。
- 三种安装包均构建并通过包检查，格式检查与离线 sanitizer/本地化检查通过。roothide 真机日志确认取得 1080 × 1920 相机帧并通过 Vision 识别；用户确认此前无法识别的二维码已弹出激活确认框。该结果验证扫码，不代表后续 profile 下载已成功。

## 1.3.10 — build 1310

### English

- Add the SIMHarbor source repository to About, with English and Chinese labels and the URL `https://github.com/Officeyutong/SIMHarbor`.
- Format all project-owned native, Python and shell sources using clang-format 22, Ruff and shfmt. Add shared formatting configuration and a reproducible format/check command, including Logos syntax handling. Localization source checks now tolerate formatted line breaks.
- Include the CI and three-package corrections described under 1.3.9. All three final packages build and pass package validation; offline sanitizer tests, resolver fixture replay, release-policy and archive extraction tests, formatting checks and workflow lint pass.
- Installed the final roothide package on the phone: service connection, reading five profiles, recovery after an injected acceptance error and bilingual About repository rows passed; the profile baseline remained unchanged. Rootful/rootless have package checks only.

### 简体中文

- 关于页新增 SIMHarbor 源码仓库入口，提供中英文标签，地址为 `https://github.com/Officeyutong/SIMHarbor`。
- 使用 clang-format 22、Ruff 和 shfmt 统一项目自有原生、Python 与 shell 代码排版，加入共享配置及可重复执行的格式化/检查命令，并保留 Logos 语法。本地化源码检查支持格式化后的换行。
- 包含 1.3.9 下记录的 CI 和三种安装包修复。最终三种包均构建并通过包校验；离线 sanitizer 测试、解析器样本回放、发布策略与解包测试、格式检查及工作流语法检查通过。
- 最终 roothide 包已安装到手机，服务连接、读取五张卡片、模拟接收错误后的恢复及关于页双语仓库入口均通过，卡片列表保持一致。rootful/rootless 目前仅完成包检查。

## 1.3.9 — build 1309

### English

- Fix CI bootstrap: official Frida Gum archives use `./`-prefixed member names. Normalize those names while preserving checksum verification and rejecting duplicate or non-regular entries. Add extraction regression tests.
- Build independent rootful, rootless and roothide packages using the pinned roothide/Theos. Every push uploads per-scheme artifacts; a version-gated release publishes all three debs only after all variants succeed, with combined checksums and per-scheme provenance.
- Generate the install script with the correct app path, select the scheme's Debian architecture and substrate dependency, and include the four app entitlements required by the roothide Developer README. Verify package contents and the versioned arm64e slice before collecting artifacts.
- All three packages built and passed local package verification. Offline sanitizer tests, CI release-policy tests, archive extraction tests and workflow lint passed. On the roothide phone, 1.3.9 connected, read five profiles, recovered after an injected acceptance failure, and preserved the profile baseline. Rootful/rootless runtime compatibility still needs devices with those jailbreaks.

### 简体中文

- 修复 CI 初始化失败：官方 Frida Gum 压缩包成员名带 `./` 前缀。规范化名称后提取，保留校验和验证，拒绝重复或非普通文件，并添加解包回归测试。
- 使用固定版本 roothide/Theos 分别构建 rootful、rootless、roothide。每次 push 上传各方案 artifact；版本号触发的 release 要求三个方案全部成功，再发布三个 deb、合并校验和和分方案构建信息。
- 按方案生成正确的安装脚本 App 路径，选择 Debian 架构和 substrate 依赖，补齐 roothide Developer README 要求的四项 App 权限。收集产物前检查包内容及 arm64e ABI 版本标记。
- 三种包均已在本地构建并通过包检查；离线 sanitizer 测试、CI 发布策略测试、解包测试和工作流语法检查通过。roothide 真机上的 1.3.9 已连接服务、读取五张卡片，并在模拟接收连接失败后恢复，卡片列表保持一致。rootful/rootless 运行兼容性仍需对应越狱设备验证。

## 1.3.8 — build 1308

### English

- Retry app IPC socket creation and listener startup after failure. Recreate the listener after acceptance errors instead of repeatedly using a broken socket. This addresses a recovery defect that could leave the app reporting a disconnected card service despite staying in the foreground.
- Log listener errors with OS error text and number. Request execution is not automatically replayed after disconnection.
- Keep the shared TCP port in the public wire header, independently of generated pairing material.
- Add [English](IPC.md) and [Chinese](IPC.zh-CN.md) documentation of the actual IPC transport, handshake, framing, operations, timeouts, limitations and troubleshooting.
- Local version/documentation/privacy checks and Objective-C syntax checks pass. Full package building and real-device reconnect validation are pending; this release has not been installed or validated on the phone locally.

### 简体中文

- App 创建 IPC socket 或启动监听失败后自动重试；接收连接出错后重建监听，避免反复使用失效 socket。此改动修复了一处可能导致 App 保持前台仍持续提示未连接的恢复缺陷。
- 监听错误日志包含系统错误文本与编号。断连后不会自动重放卡片操作。
- 公共通信头文件独立定义 TCP 端口，不再依赖生成的配对材料。
- 新增通信协议[英文](IPC.md)及[中文](IPC.zh-CN.md)文档，说明实际传输方式、握手、报文边界、操作、超时、限制和排查方法。
- 本地版本、文档、隐私与 Objective-C 语法检查通过；完整打包和真机重连验证仍待完成，本地尚未安装或验证这个版本。
