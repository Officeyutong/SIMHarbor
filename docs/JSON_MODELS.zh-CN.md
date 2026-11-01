# 共享 JSON 模型

[English](JSON_MODELS.md) | **简体中文**

SIMHarbor 1.3.20 使用随源码提供、未修改的 **nlohmann/json 3.12.0** 单头文件，处理项目自有运行时代码中的全部 JSON 解析与序列化。libeuicc 保留上游 C/cJSON 实现；Python 构建／测试工具继续使用 Python 标准 JSON 模块。

## 文件与职责

| 文件 | 职责 |
|---|---|
| [Protocol.hpp](../shared/Protocol.hpp) | App/Tweak 共用的操作／阶段枚举、握手、请求、回复、卡槽、固件报告、HTTP 状态及文档结构体。 |
| [JSON.hpp](../shared/JSON.hpp) | 有界解析，字段、整数、数组、map 和可选值的类型检查。 |
| [Framing.hpp](../shared/Framing.hpp) | LF 分帧收发，直接反序列化为协议结构体。 |
| [JSONFoundation.h](../shared/JSONFoundation.h) | Foundation 界面／诊断数据与 nlohmann DOM 的转换，不引入第二个 JSON 解析器。 |
| [Bridge.mm](../viewer/Bridge.mm) / [Apdu.mm](../tweak/Apdu.mm) | 类型化 IPC API 和请求分派。 |

需要使用 C++ 模型的项目文件按 Objective-C++ 编译；公开 C 辅助函数保留 C 链接，libeuicc 仍按 C 编译。UIKit 卡片／配置字典及 NSError 快照保留为 Foundation 模型，不再承担协议解码；卡槽列表在 App 选择逻辑中也使用结构体。

## 类型化协议流程

`Request` 包含经过检查的 `Operation`、请求 ID 和操作参数。`Request::open`、`Request::transmit`、`Request::status` 等工厂让调用目的更明确；桥接层发送前分配新的 ID。

`Reply` 包含 ID／成功／错误外壳，并用 `std::variant` 保存具体操作回复：`ResolverReply`、`SlotsReply`、`StatusReply`、`OpenReply`、`TransmitReply`，关闭操作使用空载荷。请求类型决定回复应满足哪个 schema，桥接层还会核对关联 ID。业务代码直接访问结构体成员，而不是读取字符串键字典。

`Phase` 由 App/Tweak 共用，仍编码为原有的 0～4；`Operation` 保留原字符串值。固件报告保持原有扁平字段，包括较短的初始化报告。解析位置使用字符串／无符号整数 variant，因为地址字符串和活成员数字偏移原本就采用不同表达。

模型按需使用 `NLOHMANN_JSON_SERIALIZE_ENUM` 和 `NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE`。反序列化使用显式检查的 `read` 函数，在取值前验证类型和范围，避免因预期的畸形输入而在 CommCenter 内进行 C++ 异常展开。缺少必填字段会报错；明确可选的字段可缺省或为 null。未知字段忽略，以兼容未来增添字段。

## 输入校验与分帧

- 要求对象／数组形状、字符串和布尔类型匹配；布尔或浮点不能冒充整数卡槽，数值必须落在目标整数类型范围内。
- 检查操作码、阶段范围、正逻辑槽、硬件槽、通道号、十六进制字段及卡槽映射唯一性；未知操作不会回落到有效的默认操作。
- 拒绝非法 JSON／UTF-8、重复对象键及超过 64 层的嵌套，包括未知字段内部；对象键顺序无关。
- socket 帧最大 **262,144 字节，包含末尾 LF**，即收发双方都最多接受 **262,143 字节 JSON**，修复原发送／接收上限相差一个字节的问题。
- 握手／请求／回复不满足 schema 时关闭该连接；回复 ID 非法或不匹配也断开，不自动重放请求。

报文字段名、HMAC 构造、请求 ID、端口及 APDU 传输语义保持不变，完整协议见 [IPC 文档](IPC.zh-CN.md)。App 和扩展仍需来自同一次配对构建。

## 其他 JSON 边界

内置说明反序列化为 `std::vector<Article>`；项目自有的运营商 HTTP 状态检查使用 `HTTPEnvelope`／`HTTPHeader`／`ExecutionStatus`／`StatusCodeData`，libeuicc 真正的 RSP 请求／响应处理不变。错误详情、日志和 CLI 快照统一通过 nlohmann 序列化，现有界面／诊断数据经 Foundation 适配层转换。该层保留布尔、有符号／无符号整数、Unicode 及内嵌 NUL，拒绝不支持的对象和非有限数值。

## 依赖与检查

来源 URL、版本及 SHA256 记录在 [vendor/nlohmann/PROVENANCE.json](../vendor/nlohmann/PROVENANCE.json)。MIT 许可随源码及 App 开源声明提供，不改变 libeuicc 的许可。

`python3 tests/check_offline.py` 运行 `tests/test_json.cpp`，在 ASan/UBSan 下覆盖结构体往返、错误类型／范围、重复／过深输入、原有报文字段、分片帧、截断输入及大小边界。已安装程序的 `--json-check` 使用模拟数据验证 Foundation 转换和类型化回复，不操作卡片或网络；原有错误、通知模拟检查入口保留。真实 CommCenter／驱动通道仍需真机验证。
