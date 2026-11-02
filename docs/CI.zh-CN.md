# 构建与发布机制

[English](CI.md) | **简体中文**

CI 使用 Ubuntu 24.04，以三个独立矩阵任务构建 rootful、rootless、roothide。`ci/install_linux_deps.sh` 使用 LLVM 官方签名 apt 仓库安装 Clang 22；`ci/bootstrap.py` 准备固定提交的 roothide/Theos、SDK 16.5 和经 SHA256 校验的 Linux 链接工具与 Gum devkit。Gum 解包兼容官方文件名的 `./` 前缀；包方案与安装路径见[安装包方案](PACKAGING.zh-CN.md)。

安装依赖时还需 `libplist-utils`，其运行库供工具链的 `plistutil` 使用。此前 CI 在最终打包时报缺少 `libplist-2.0.so.4`；本地预装了该库，所以本地构建未暴露遗漏。`build.sh` 现在先运行 `ci/check_packaging_tools.py`，按实际构建 PATH 调用转换器，验证 XML 和 OpenStep 字符串表能原地转换成二进制 plist 且保留中文值；运行库缺失会在编译前输出原因及安装提示。此检查每次构建执行，不受工具链缓存命中影响。

事件策略：任意 push 都构建及上传 artifact。默认分支 push 才比较该 push 的 `before` 提交与当前 `VERSION`，所以多提交 push 不会漏掉前面的版本修改。初始 push 从不存在的版本进入第一个版本会发布；版本未变、仅构建号变化、tag/其他分支或手动运行都不发布。缺失旧提交时保守停止发布，不阻止构建。

每种方案独立上传 artifact，某个任务失败不会取消其他任务。三种构建全部成功才进入独立发布 job，合并同一 workflow run 的三份 artifact，核对每个包的 SHA256，再创建 `vVERSION` release，同时附上三个 deb、合并校验和与分方案构建信息。同名 release 已存在则保留，不覆盖旧构建。artifact 含 deb、校验与公开构建来源；不会包含源码工作目录、生成的配对头、下载依赖或私有捕获。失败时上传已生成的诊断。

`VERSION` 是正式版本，`BUILD_NUMBER` 是 App 构建号，两者映射到自动生成的包 metadata。发布逻辑只由 `VERSION` 变化触发。例：改 1.3.7 为 1.3.8 并 push 到默认分支，会发布 v1.3.8；只改 UI 后 push，只有 artifact。

工作流中第三方 actions 固定到提交，公开二进制依赖固定校验值。缓存只保存公开工具，不缓存配对材料。不要在 workflow env、仓库变量或源码里填设备密码和激活码；此构建不需要它们。
