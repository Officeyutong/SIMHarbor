# 内嵌 Frida Gum／Capstone

[English](README.md) | **简体中文**

使用未修改的官方 Frida Gum devkit **17.25.0**，包含 iOS arm64 和带 ABI 版本的 arm64e。`PROVENANCE.json` 记录来源 URL、原始压缩包／静态库 SHA256；两种架构的头文件和静态库均保留，便于复现链接。

扩展仅引用静态库内的 Capstone 5 ARM64 解码器。显式注册架构并设置 libc 分配函数，避免初始化 Gum／GLib。模块级私有符号查询直接使用系统 CoreSymbolication；早期全进程 Gum 枚举曾超过 CommCenter 的内存限额。Tweak 不包含 GumJS、JavaScript 运行时，也不需要 Frida server；Hook 仍通过现有 Substrate 接口安装。链接参数限制导出，防止内嵌 Gum／GLib／Capstone 符号替换另行附加的 Frida agent 符号。

[源码](https://github.com/frida/frida-gum/tree/17.25.0)与[上游构建依赖说明](https://github.com/frida/frida)。`COPYING` 保留上游 wxWindows 许可及内嵌声明，`COPYING.LIB` 为原有 LGPL-2.1 许可文本；没有修改上游库。重建时使用该发布版本的 Frida 构建环境及 iOS SDK，重新生成 ios-arm64／ios-arm64e gum devkit，验证 ABI 后再替换。
