# Release notes / 版本记录

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
