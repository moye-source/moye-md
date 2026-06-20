# 墨页推广素材

这份文档用于公开推广墨页（Moye）。内容可以直接复制到社区、社交媒体、博客或项目介绍页。

推广时请保持真实：墨页是早期开源项目，可以用于本地 Markdown 编辑，但还不是签名、公证、完全稳定的正式产品。

## 一句话介绍

墨页（Moye）是一款用 SwiftUI 和 AppKit 开发的原生 macOS Markdown 编辑器，专注本地文件、中文输入、实时预览和 macOS 文档型软件体验。

## 短介绍

墨页（Moye）是一个开源的原生 macOS Markdown 编辑器。它使用 `NSTextView` 作为编辑器核心，优先保证中文输入法、选区、撤销栈和本地文件编辑的稳定性；右侧预览使用 `WKWebView` 单独渲染，支持实时预览、文件树、大纲、搜索、图片、表格、数学公式、Mermaid 图表和常见导出入口。

项目目标不是做网页编辑器，而是做一个符合 macOS 使用习惯的本地 Markdown 写作软件：菜单栏是主要命令入口，侧栏负责文件和大纲导航，编辑区和预览区可以拖动调整宽度。

## 适合强调的特点

- 原生 macOS App，不是网页套壳
- 默认中文界面，可切换英文
- 基于 AppKit `NSTextView` 的编辑器核心
- 更重视中文输入法、撤销、选区和本地文件体验
- 文件树、大纲、搜索、实时预览在一个窗口内完成
- 支持表格、任务列表、图片、数学公式和 Mermaid 图表预览
- 开源，MIT 许可证

## 暂时不要夸大的点

- 不要说它已经是 Typora 的完整替代品
- 不要说它已经完全稳定
- 不要说它已经支持自动静默更新
- 不要说发布包已经签名或公证
- 不要承诺上架 App Store

## 项目链接

- GitHub: <https://github.com/moye-source/moye-md>
- Releases: <https://github.com/moye-source/moye-md/releases>
- 中文说明: <https://github.com/moye-source/moye-md/blob/main/README.zh-CN.md>

## 中文社区发帖模板

标题备选：

```text
我做了一个原生 macOS Markdown 编辑器：墨页 Moye
```

```text
开源一个用 SwiftUI/AppKit 写的 macOS Markdown 编辑器
```

正文：

```text
大家好，我最近在做一个原生 macOS Markdown 编辑器，名字叫墨页（Moye）。

项目地址：
https://github.com/moye-source/moye-md

它的方向是做一个符合 macOS 桌面软件习惯的本地 Markdown 编辑器，而不是网页套壳。现在已经支持：

- 本地 Markdown 编辑
- 默认中文界面，可切换英文
- 文件树、大纲、搜索
- 分屏编辑和实时预览
- 图片粘贴/拖拽到 assets 文件夹
- 表格行列辅助编辑
- 数学公式和 Mermaid 图表预览
- HTML、PDF、PNG、Pandoc 导出入口

编辑器核心用了 AppKit 的 NSTextView，主要是为了让中文输入法、选区、撤销栈和本地文件编辑更稳定。

现在还是早期开源版本，发布包暂未签名和公证。如果你也关心原生 macOS 写作工具，欢迎试用、提 issue、给 star 或参与贡献。
```

## X / Threads / Mastodon 短帖

中文：

```text
开源了一个原生 macOS Markdown 编辑器：墨页 Moye。

SwiftUI + AppKit，编辑器核心基于 NSTextView，重点做好中文输入、本地文件、文件树、大纲、实时预览和 macOS 文档型软件体验。

GitHub: https://github.com/moye-source/moye-md
```

English:

```text
I am building Moye, an open-source native macOS Markdown editor.

SwiftUI + AppKit, NSTextView-based editing, local files, file tree, outline, live preview, table helpers, images, MathJax, and Mermaid preview.

GitHub: https://github.com/moye-source/moye-md
```

## Hacker News / Reddit 模板

Title:

```text
Show HN: Moye, a native macOS Markdown editor built with SwiftUI and AppKit
```

Post:

```text
Moye is an open-source native macOS Markdown editor focused on local writing.

It is built with SwiftUI and AppKit. The editor core uses NSTextView to keep text input, selection, undo, and input-method behavior stable. Live preview is rendered separately with WKWebView.

Current features include local Markdown editing, file tree browsing, outline, file/content search, split editor/preview mode, local images, table helpers, MathJax, Mermaid preview, and export entries.

It is still an early project. The current build is unsigned and not notarized, but the source code and release package are available on GitHub:
https://github.com/moye-source/moye-md
```

## Product Hunt 简短介绍

```text
Moye is a native macOS Markdown editor for local writing. Built with SwiftUI and AppKit, it focuses on reliable text editing, local files, live preview, file tree navigation, and a document-first Mac experience.
```

## README 引流句

```text
如果你喜欢原生 macOS 写作工具，欢迎 star、试用、提交 issue 或参与贡献。
```

English:

```text
If you care about native Mac writing tools, stars, issues, feedback, and contributions are welcome.
```

## 推广渠道建议

- GitHub topics：继续保留 `macos`, `markdown-editor`, `swiftui`, `appkit`, `native-macos`
- V2EX：适合第一次中文开发者曝光
- 少数派 Matrix：适合写一篇更完整的开发记录
- 小众软件：适合稳定一点后投稿
- Hacker News：适合 `Show HN`
- Reddit：可以发到 `r/macapps`、`r/Markdown`、`r/swift`
- X / Mastodon：适合短帖持续记录开发进展
- GitHub Release：每个版本写清楚新增功能、修复和已知问题

## 发布节奏

第一轮：项目首次公开

- 发 V2EX 和 X / Mastodon
- README 保持清楚，Release 可下载
- 收集第一批 issue

第二轮：稳定性更新

- 修复用户反馈的问题
- 发 `v0.1.1` 或 `v0.2.0`
- 写一篇“为什么做原生 macOS Markdown 编辑器”

第三轮：签名和公证后

- 再投少数派 Matrix、小众软件、Product Hunt
- 强调安装体验改善
- 增加截图或短视频演示

## 推广注意事项

- 不刷屏，同一社区一段时间只发一次主帖
- 认真回复反馈，尤其是崩溃、打不开、输入法、图片路径问题
- 不和 Typora、Obsidian、VS Code 做攻击式对比
- 重点说清楚“为什么原生”“为什么本地”“为什么开源”
- 用户反馈的问题优先变成 issue，再进入版本计划
