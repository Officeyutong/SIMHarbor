# App 内离线手册

文档源为 `index.json` 和 `en/`、`zh-Hans/` 下相同 ID 的 Markdown。当前五篇：guide、signals、architecture、porting、validation。

`python3 scripts/build_docs.py` 生成 App 的 `viewer/Resources/Documentation-{en,zh-Hans}.json`；`build.sh` 自动生成。`python3 scripts/build_docs.py --check` 检查资源是否最新；总离线检查也包含此项。

阅读器使用原生 UITextView，支持标题、段落、列表、行内代码、粗体、text 代码块及双列表格（按条目展开）。内容可复制，目录支持标题/摘要/正文搜索。没有 WebKit、JavaScript、在线依赖或执行文档示例的路径。

技术内容来自主文档 ARCHITECTURE_PORTING.md，中文 architecture/porting 为该文档的阅读版，英文为对应翻译。修改技术路线时同步维护两种语言；生成器会核对所有十六进制偏移、UUID 与 Get EID 示例。图示使用离线文本流程，不嵌入 Mermaid 或仓库相对链接。

文档只记录匿名技术结论。真实设备地址、登录凭据、激活码、卡片标识、个人卡片列表、线路归属和含这些内容的截图不得写入文档或示例；使用 DEVICE_HOST、example.invalid 等占位符。公开型号、系统版本、镜像 UUID、指令及偏移可保留。生成器和 tests/check_docs_privacy.py 自动检查常见泄漏；历史文档已脱敏，不再作为完整原始证据。
