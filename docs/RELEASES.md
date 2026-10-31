# Release notes / 版本记录

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
