# 墨页 Moye

墨页（Moye）是一款原生 macOS Markdown 编辑器，目标是提供专注、本地、可靠的 Markdown 写作体验。

项目使用 SwiftUI 和 AppKit 开发。编辑器核心基于 `NSTextView`，用于保证文字输入、选区、撤销栈和中文输入法体验；右侧预览使用独立的 `WKWebView` 渲染。

[English README](README.md) · [免责声明](DISCLAIMER.md) · [许可证](LICENSE)

## 当前状态

墨页还是早期开源项目，可以用于本地 Markdown 编辑，但还不是正式稳定版。

目前优先目标不是堆功能，而是先把一个 macOS 文档型软件应该有的基础能力做好：本地文件、菜单栏、撤销重做、未保存提示、文件树、大纲、预览、导出、图片和表格。

## 下载

请从 GitHub Releases 下载打包好的 macOS App：

<https://github.com/moye-source/moye-md/releases>

发布包格式类似：

```text
Moye-0.1.0-macOS.zip
```

当前版本暂未做 Apple Developer ID 签名和公证。macOS 可能会提示“无法验证开发者”或阻止首次打开。请只运行你信任的构建包，并在使用前阅读 [免责声明](DISCLAIMER.md)。

## 在线更新

墨页支持从 GitHub Releases 检查新版本。

检查地址：

```text
https://api.github.com/repos/moye-source/moye-md/releases/latest
```

如果发现新版本，墨页会打开 GitHub Releases 下载页面或对应的下载资源。当前不会静默替换本机 App。真正自动更新功能需要后续结合签名、公证和更新校验机制再做。

GitHub 可以作为开源项目的在线资源来源：

- 代码托管：GitHub Repository
- 安装包下载：GitHub Releases / Release Assets
- 更新检查：GitHub Releases API
- 自动打包：GitHub Actions

不建议把安装包直接长期提交进源码仓库。更好的方式是把源码放仓库，把 `.app.zip` 放 GitHub Releases。

## 主要功能

- 原生 macOS App
- 默认中文界面，可切换英文
- 本地 Markdown 源码编辑
- 基于 AppKit `NSTextView` 的编辑器核心
- Markdown 语法高亮
- 分屏、仅编辑、仅预览模式
- 编辑区和预览区可拖动调整宽度
- 实时 HTML 预览
- 编辑和预览按源码行同步滚动
- 根据标题生成文档大纲
- 文件夹侧栏，显示完整文件树
- 文件名和文件内容搜索
- 快速打开
- 未保存修改状态
- 撤销、重做、剪切、复制、粘贴、全选、查找、替换
- 标准 macOS 菜单栏命令
- 设置入口位于 App 菜单，快捷键 `Command-,`
- 插入标题、目录、代码块、表格、任务列表、图片
- 图片粘贴和拖拽到 `assets/` 文件夹
- 表格行列增删辅助功能
- HTML、PDF、无样式 HTML、PNG、Pandoc 导出入口
- 支持 front matter、表格、任务列表、脚注、链接、本地图片和常见行内样式预览
- MathJax 数学公式预览
- Mermaid 图表预览
- 专注模式、打字机模式、行号、自动配对
- 词数、字符数、行数、阅读时间统计

## 系统要求

- macOS 13 或更高版本
- 开发需要安装 Xcode 和 macOS SDK
- Pandoc 导入/导出需要本机安装 `pandoc`

唯一支持的工程入口：

```text
NativeMarkdownEditor.xcodeproj
```

旧的 Swift Package 原型入口已经删除，不要再使用 `swift run`、`swift build` 或 `.build/NativeMarkdownEditor.app` 验证真实编辑体验。

## 外部资源说明

墨页是原生 App，但目前部分能力依赖外部资源：

- MathJax 预览从 jsDelivr 加载。
- Mermaid 预览从 jsDelivr 加载。
- Pandoc 导入/导出依赖本机 `pandoc` 命令。
- 在线更新检查读取公开 GitHub Releases 信息。

后续计划把 MathJax/Mermaid 打包到 App 内，并提供更完整的 Pandoc 路径设置和更新校验。

## 构建

用 Xcode 打开：

```bash
open NativeMarkdownEditor.xcodeproj
```

选择 `NativeMarkdownEditor` scheme，然后运行。

命令行构建和测试：

```bash
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' build
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' test
```

构建并打开本地 Debug App：

```bash
./RunNativeMarkdownEditor.command
```

打包发布 zip：

```bash
./scripts/package-macos.sh 0.1.0
```

输出位置：

```text
dist/Moye-0.1.0-macOS.zip
```

## 发布流程

仓库已经配置 GitHub Actions。推送 `v` 开头的 tag 时，会自动打包 macOS App 并创建 GitHub Release。

示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

Release workflow 会生成并上传：

```text
Moye-0.1.0-macOS.zip
```

## 设计原则

- 优先遵循 macOS 原生桌面软件习惯。
- 菜单栏是核心命令入口。
- 侧栏只做文件树、大纲和搜索等导航。
- 文本输入、选区、撤销栈和中文输入法优先交给 AppKit 控制。
- 编辑器和 HTML 预览保持分层，不把预览逻辑耦合进文本输入核心。
- 真正 Typora 式体验需要 Markdown AST、选区映射和撤销栈配合，不用简单字符串替换冒充。

## 贡献

欢迎贡献，但请保持项目方向一致：

1. 保持 macOS 文档型软件习惯。
2. App 结构优先 SwiftUI，精细文本编辑优先 AppKit。
3. 编辑器、渲染器、文件状态、导出逻辑保持分离。
4. 行为改动需要补测试。
5. 提交 PR 前运行 build 和 test。

```bash
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' build
xcodebuild -project NativeMarkdownEditor.xcodeproj -scheme NativeMarkdownEditor -destination 'platform=macOS' test
```

## 许可证

墨页使用 [MIT License](LICENSE) 开源。
