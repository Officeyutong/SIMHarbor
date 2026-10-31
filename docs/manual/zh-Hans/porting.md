# 移植指南与运行时定位

## 1.3 的运行时解析

扩展使用 Frida Gum 17.25.0 devkit 内的 Capstone 5 解码 ARM64；私有符号只在目标驱动模块中通过 CoreSymbolication 枚举。普通运行不需要 Frida server、JavaScript 或电脑。Hook 仍使用 Substrate。

解析分两步：先分析镜像得到 18 项代码位置/字段，再从只读的活对象识别 2 项字段。每项必须有唯一候选，报告保留来源与失败状态。没有旧数值偏移回退。卡片页的管理菜单提供「固件解析」，可以刷新和复制报告；读取报告本身不发送 APDU。

- Mach-O：运行时读取加载地址、代码段、UUID 和 LC_FUNCTION_STARTS；只接受目标镜像内的函数起点。
- 符号与调用关系：定位驱动打开/命令/关闭，通过 block 指令和调用图识别编码、响应、QMI 回调及其捕获字段。
- C++ RTTI 与虚表：查找 SubscriberSimController 和 APDU 闭包，再沿虚方法、worker、闭包构造关系确定 sender、worker、完成回调。
- 指令语义：从 worker 访问推导 SimInfo vector、逻辑槽字段和状态函数；就绪判断直接使用导出的 isSimReady，不固定状态枚举。
- 活对象：捕获导出的 Registry getter，有限遍历服务 map 的链，通过已识别虚表确认唯一控制器；无需旧 map/node/typeinfo/虚表槽偏移。
- 驱动指针必须精确匹配具体驱动 RTTI，排除名称中也包含驱动类的 shared_ptr 控制块。硬件槽字段在多个 SimInfo 节点中交叉验证，逻辑槽和硬件槽分别使用。

## 当前解析结果样本

下表是 iPhone14,5 / iOS 17.2.1 的研究样本，不是配置或跨版本常量；地址相对于各自镜像基址。完整实现位于 tweak/ResolverCore.cpp、tweak/RuntimeResolver.mm 和 tweak/Apdu.mm。

| 项目 | 本机构建的解析结果 |
|---|---|
| CommCenter UUID | 10bdb2fd04e33fcea0a188d064801df2 |
| 驱动 UUID | 571c9998ee7c3d9e946f779aee761332 |
| sender / worker | CommCenter +0x7e4568 / +0x7ff250 |
| 控制器虚表 / 完成回调 | CommCenter +0x175fb78 / +0x803a74 |
| SimInfo 状态函数 | CommCenter +0x11c3c10 |
| SimInfo vector / 逻辑槽 | 控制器 +0xa8 / SimInfo +0x24 |
| 驱动打开 / 命令 / 关闭 | 驱动 +0x168858 / +0x1693e0 / +0x16a7a4 |
| 编码 / QMI / 响应回调 | 驱动 +0x169bb8 / +0x16a214 / +0x16a43c |
| 编码通道 / 响应硬件槽 / 响应通道 | block +0x30 / +0x30 / +0x34 |
| QMI 错误字段 | 结果 +0x4 |
| 控制器驱动指针 / SimInfo 硬件槽 | 活对象 +0x68 / +0x20 |
| 就绪判断 / Registry | 导出的 subscriber::isSimReady 和 Registry::getServiceMap |

## 支持新版本的流程

1. 记录目标设备、基带、架构及两个镜像 UUID；先安装仅诊断的构建，保存固件解析报告。未知 UUID 对仍允许分析，但不会装 Hook 或发送卡片命令。
2. 若代码位置能唯一解析，重点核对私有函数签名、参数顺序、C++ 按值/引用传递、block 捕获语义、回调生命周期和 PAC。当前编译实测 shared_ptr 为 16 字节、std::function 为 32 字节；早期 Frida 脚本分配的 48 字节不是该类型 sizeof。对象大小相同也不能证明 ABI 一样。
3. 在 shared/Firmware.h 的 SHApprovedAbis 中添加经核对的 UUID 对和对象大小；正常情况下无需填数值偏移。若模式不匹配，应修改对应语义规则并添加镜像回放/反例，保持旧版本回归通过。
4. 核对注入环境、arm64/arm64e、Substrate 及 rootless/roothide 打包。先只读核对活对象、逻辑/硬件槽映射、Get EID、列表、61xx、关闭通道及断连恢复。
5. 再使用已授权且可重新下载的测试 profile，验证下载、启用、停用、恢复和删除，并逐项比较基线。当前默认 slot 2 不代表其他设备的实体卡槽。
6. 单独测试网络权限、GSMA TLS、相机/相册、前后台与重启。App 的标准 LPA/UI 通常可复用；内部 eUICC、MEP、不同基带和 USB 读卡器需要另做通路适配。

运行时定位减少了地址和字段维护，不能自动证明调用约定或卡槽语义。当前只批准上述 UUID 对。驱动符号缓存缺失、RTTI 被裁剪、指令形态改变、对象候选不唯一都会拒绝操作。活对象算法目前要求 2–16 个 SimInfo 节点及唯一的 1–3 硬件槽字段；单节点或不同映射需要调整规则后实测。

## 资源和验证约束

CommCenter 的内存限额很低。早期全进程 Gum 符号枚举触发内存高水位终止，已回退并移除；最终使用模块级 CoreSymbolication，显式注册 Capstone ARM64 和 libc 分配函数，避免 Gum/GLib 全局缓存。报告中的 maxMeasuredFootprintBytes 是若干阶段的采样最大值，不是连续测得的进程峰值。解析失败显式返回错误，不依赖 C++ 异常展开。

新解析器需要重新完成写卡/切换回归；本轮只读验证不能替代先前 1.1.4 的完整写入测试，也不能证明其他系统兼容。
