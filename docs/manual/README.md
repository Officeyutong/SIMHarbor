# 双语使用说明与仓库技术文档

App 仅打包 `index.json` 中的 guide：`en/guide.md` 和 `zh-Hans/guide.md`。原生「使用说明」标签直接显示文章，可选择文字、复制全文，并适配动态字体；不再显示多篇文档目录或搜索界面。关于页的帮助入口也打开这份使用说明。

`python3 scripts/build_docs.py` 生成 `viewer/Resources/Documentation-{en,zh-Hans}.json`，每种语言恰好一篇使用说明；`build.sh` 自动调用。`--check` 检查资源是否最新，离线检查也包含此项。

signals、architecture、porting、validation 的双语 Markdown 保留为仓库资料，不进入 App 资源。生成器仍检查技术路线中的偏移/UUID 与两语言 architecture/porting 一致，以及 signals 的 Get EID 示例。Patchfinder 原理文档位于仓库 docs/PATCHFINDER.md 和 docs/PATCHFINDER.zh-CN.md，也不随 App 打包。

使用说明阅读器采用原生 UITextView，支持标题、段落、列表、行内代码、粗体、text 代码块及双列表格。它不执行示例，不依赖 WebKit、JavaScript、卡片连接或网络。App 的固件解析报告和开源许可仍是独立功能。

文档只记录匿名技术结论。真实设备地址、登录凭据、激活码、卡片标识、个人卡片列表和线路归属不得写入文档；使用 DEVICE_HOST、example.invalid 等占位符。公开型号、系统版本、镜像 UUID、指令、偏移和明确要求公开的开发者信息可以保留。文档生成器及 tests/check_docs_privacy.py 检查常见泄漏。
