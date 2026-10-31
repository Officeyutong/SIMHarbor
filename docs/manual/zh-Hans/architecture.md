# 技术路线与移植

当前实际验证基线：iPhone 13（iPhone14,5）、iOS 17.2.1 / 21C66、roothide，实体 eSTK eUICC 位于 slot 2。1.1.4 完成了原生 测试条目 下载/重命名/启用/停用/恢复/删除回归；1.1.7 完成最终只读检查。1.2.1 已在真机完成文档/双语、日志和只读自定义信令验证。1.2.2 更新内置验证记录，传输核心未变。

## 当前路线

```text
UIKit 界面 / 原生 libeuicc LPA
  ├─ ES9+ → NSURLSession HTTPS → 运营商服务器
  └─ ES10 → 本机 HMAC IPC → CommCenter 原生扩展
                    → subscriber / QMI 驱动
                    → 实体 eUICC 的 ISD-R
APDU 与 HTTP 应用层收发 → 英文日志
```

App 在手机本地执行 LPA，扩展只负责卡槽/逻辑通道/APDU。Frida 是研究和调试工具，普通使用不依赖它，也不需要电脑做 APDU 或 HTTP 中转。UI 操作共用串行队列，写卡、切换、读卡和自定义请求不会并发占用通道。

CommCenter 的高层 sender 接收的是 **AID**，不是任意原始 APDU。扩展借它建立 ISD-R 会话，拦截驱动准备关闭通道的流程以保持会话；后续替换驱动生成的 APDU 数据，捕获原始响应，再在 App 请求结束时关闭并释放原流程的回调。SIM 处于 inactive 状态时，改用驱动入口打开管理通道，支持停用后继续读卡或恢复线路。

App/扩展之间为有界 JSON 帧及随机挑战的双向 HMAC 认证，监听限于本机回环。HMAC 不隔离越狱 root；配对密钥随本项目的 App/扩展共同构建。扩展通过模块级 CoreSymbolication、Frida devkit Capstone、RTTI 与活对象检查推导地址和字段；UUID 仅作记录；接口签名和完整代码计划检查通过后装 Hook，活对象和卡槽检查通过后才操作卡片。「固件解析」页面可查看依据，移植指南列出规则及仍需人工核对的部分。

