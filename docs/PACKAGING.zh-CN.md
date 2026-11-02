# 安装包方案

[English](PACKAGING.md) | **简体中文**

SIMHarbor 使用固定版本的 roothide/Theos，按 [roothide Developer README](https://github.com/roothide/Developer) 构建三种方案。目前源码不直接打开越狱资源路径，系统框架路径保持原样。以后若添加对越狱文件的访问，应使用文档规定的 `jbroot()`，避免写死越狱根目录。

| `SIMHARBOR_SCHEME` | Theos 方案 | Debian 架构 | App 安装路径 |
| --- | --- | --- | --- |
| `rootful` | 空 | `iphoneos-arm` | `/Applications/ESTKLog.app` |
| `rootless` | `rootless` | `iphoneos-arm64` | `/var/jb/Applications/ESTKLog.app` |
| `roothide` （默认） | `roothide` | `iphoneos-arm64e` | `/Applications/ESTKLog.app` （roothide 环境内） |

扩展安装在对应前缀下的 `Library/MobileSubstrate/DynamicLibraries`。Theos 为每种方案选择依赖库路径与安装名。App 为 arm64，扩展包含 arm64 和带 ABI 版本标记的 arm64e。Debian 架构标签用于区分越狱打包方案，不等同于可执行文件切片。

App 包含 Developer README 要求的四项权限：`platform-application`、`com.apple.private.security.no-sandbox`、`com.apple.private.security.storage.AppBundles` 和 `com.apple.private.security.storage.AppDataContainers`。安装后脚本按方案生成正确的 App 路径，更新应用注册并重启 CommCenter，蜂窝网络会短暂中断。

## 本地构建

按 README 安装依赖后运行：

```sh
for scheme in rootful rootless roothide; do
    SIMHARBOR_SCHEME="$scheme" bash build.sh
    python3 ci/collect_artifacts.py --scheme "$scheme"
done
```

每次构建都会先清理，避免不同方案混用缓存。校验程序检查真实 deb 元数据、App/扩展路径、安装后注册路径、内置使用说明和 Mach-O 切片，包含 arm64e 的 ABI 版本标记。规范命名的安装包、分方案校验和与构建信息放入忽略的 `dist/`。双方二进制必须来自同一个安装包；不同构建会生成不同配对值。

## CI 与兼容范围

每次 push 运行三个独立任务，每种方案上传一份 artifact，失败时上传已有诊断。Release 仍只在默认分支版本号变化时触发，要求三个任务全部成功，并同时发布三种 deb 和经过验证的校验和。三种包均使用同一套运行时能力检查，不再使用固件 UUID 白名单。现有手机只能测试 roothide；rootful/rootless 的包结构检查不代表已验证对应越狱环境的真机兼容性。
