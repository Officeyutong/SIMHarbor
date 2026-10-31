# 芯舟 · SIMHarbor

在越狱 iPhone 上管理可移除 eUICC 的原生 App 与 CommCenter 扩展。开发者：[officeyutong](https://github.com/officeyutong)。

支持卡片列表、下载、启用/停用、昵称、删除、通知管理、二维码相机/图片识别、连续及点击对焦、中英文界面、离线文档和原始 APDU/DER 控制台。日常运行不需要电脑或 Frida server。

当前已核对的私有 ABI：iPhone 13 / iOS 17.2.1（21C66），roothide。运行时解析地址、字段和活对象；未批准的镜像 UUID 对只提供诊断，不操作卡片。其他固件需要验证，不能仅移除 ABI 门禁。关于页面显示安装版本、构建号和开源许可。

## Linux 构建

使用 Ubuntu 24.04、Clang 22、固定版本 roothide/Theos、SDK 16.5 和旧版 Darwin 链接工具。依赖会下载到忽略目录，不需要设备账号、激活码或 Apple 开发者签名证书。

```sh
bash ci/install_linux_deps.sh
python3 ci/bootstrap.py
python3 scripts/sync_version.py
python3 tests/test_ci_policy.py
python3 tests/check_offline.py
bash build.sh
```

deb 输出在 `packages/`。公开依赖的来源、提交号和校验值见 `ci/dependencies.json` 与 `vendor/frida-gum/PROVENANCE.json`。构建时为 App 和扩展生成同一份随机 IPC 配对材料，构建结束删除头文件；不要拆开安装来自不同构建的 App 和扩展。

## 自动打包与发布

GitHub Actions 文件：`.github/workflows/build.yml`。

- 每次 push（所有分支和标签）都运行构建并上传 artifact；手动运行也上传。成功构建包含 deb 和 SHA256，失败构建上传已有诊断日志。
- 仅默认分支的 push，且最终 `VERSION` 与该次 push 之前不同，才发布 `v版本号` release。一次 push 中间包含版本提交、最后还有其他提交，也能正确识别。
- 首次默认分支 push 引入 `VERSION` 视为版本变化，创建首个 release。仅修改代码、文档或 `BUILD_NUMBER` 不发布。
- 分支/tag push 和手动运行不发布；已有同名 release 不覆盖。无法取得旧提交时保留构建/artifact，停止自动发布。
- 普通构建只使用只读仓库权限；独立发布 job 才有 `contents: write`。不需要配置自定义 token。请允许仓库运行 Actions；仓库/组织策略仍可限制发布权限。

发布新版时修改 `VERSION`，并按需递增 `BUILD_NUMBER`。`control` 和 App 的 `Info.plist` 从 `packaging/` 模板自动生成，无需手动同步。源码版本目前为 1.3.7。

## 测试与验证范围

本地检查覆盖双语文档/隐私、编解码、异常输入、真实 libeuicc 模拟卡端流程、ASan/UBSan，以及真实 Git 历史下的 CI 发布策略。只读设备测试与完整写入测试的适用范围见 [验证记录](docs/VALIDATION.md)。CI 不连接手机，不下载或切换真实 profile。

可选的镜像回放测试：`python3 tests/check_resolver.py /path/to/resolver-fixture`，需要自己从授权设备获取的私有镜像；这些数据不纳入仓库或 CI。

## 源码与资料

- `viewer/`：UIKit App、LPA、二维码、日志、双语文档、关于页。
- `tweak/`：CommCenter 通道、Capstone/RTTI/调用图定位。
- `shared/`：协议与 ABI 批准表。
- `docs/manual/`：随包中英文手册；[移植说明](docs/ARCHITECTURE_PORTING.md)。
- `ci/`：公开依赖准备、版本发布策略、产物核对。
- `vendor/`：第三方源码、许可与来源说明；Gum devkit 的头/库在构建时经校验下载。

本仓库从清理后的源码建立新历史，不包含设备日志、研究快照、安装包历史、固件、账号凭据、激活信息或固定配对密钥。公开硬件型号、固件 UUID、技术偏移与开发者信息按用途保留。`scripts/check_public_tree.py` 检查将进入 Git 的文件，文档生成器另外检查文档隐私。

第三方许可见 `vendor/LICENSES/` 和 App 内“关于 → 开源许可”；未替第三方组件改写许可。SDK/工具链分别遵循其提供方条款。
