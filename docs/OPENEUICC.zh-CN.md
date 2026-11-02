# OpenEUICC 功能对照

[English](OPENEUICC.md) | **简体中文**

对照官方源码 https://gitea.angry.im/PeterCxy/OpenEUICC ，研究时 checkout `2cbd7a1b3f2482003ace1583b64abf4015283e5a`。依据 `app-common/src/main/res/menu/profile_options.xml`、`fragment_euicc.xml`、`notification_options.xml`、`res/xml/pref_settings.xml` 及 README；没有移植 Android UI/系统接口代码。

| 功能 | 芯舟实现与边界 |
|---|---|
| Profile 列表、下载、删除 | 原生 libeuicc；相机/相册二维码、手动输入、确认码；只删除已停用条目 |
| 启用/停用 | ES10c；切换后关闭通道并重读确认状态；UI 二次确认 |
| 修改昵称 | ES10c；最多 64 UTF-8 bytes，清空恢复卡片默认名称 |
| 卡片信息 | EID、可用存储/运行内存、固件/RSP/Profile 版本 |
| 通知 | 查看、单条/批量提交成功后移除、仅移除；安装/删除/切换自动通知分别设置 |
| 默认 SM-DP+ | 读取/设置；SM-DS 只读 |
| 下载 IMEI | 可选 15 位数字，仅本次下载使用 |
| HTTP CONNECT 代理 | 可设置无认证 HTTP 代理；保留 TLS/主机名校验；尚未实测代理服务 |
| 切换刷新、APDU MSS | 默认刷新；MSS 120/240/255，可调整 |
| 卡片重置 | 实现 EID 核对 + 输入 RESET 确认；没有在用户现有卡片上实测 |
| 操作记录 | 英文流程与原始 APDU/HTTP 信令，可导出；可能包含激活凭据（1.2.0） |
| Android OMAPI/特权系统集成、MEP、多读卡器 | 未移植；该早期对照范围仅包括已核对的 iOS 固件和实体 slot 2 |
| USB CCID、强制 TPDU | 当前 CommCenter 传输不支持 USB 读卡器 |
| 自定义 ISD-R AID | 当前扩展限定标准 ISD-R AID，未开放 |
| 开发者跳过 TLS 校验 | 不提供；采用系统信任及 GSMA 根证书 |
| SM-DS 自动发现/运营商系统设置集成 | 未实现；下载需激活码 |

“已实现”表示接口与 UI 已接通；真机验证范围单独列在 VALIDATION.md，不等于全部运营商或所有设置均已覆盖。

1.2.0 另增中英文界面和原始 APDU/DER 控制台，仅完成本地构建及离线测试。技术路线见 ARCHITECTURE_PORTING.md。
