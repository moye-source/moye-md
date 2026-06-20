# 墨页 Moye

墨页（Moye）是一款原生 macOS Markdown 编辑器，目标是提供专注、本地、可靠的 Markdown 写作体验。

项目使用 SwiftUI 和 AppKit 开发。编辑器核心基于 `NSTextView`，用于保证文字输入、选区、撤销栈和中文输入法体验；右侧预览使用独立的 `WKWebView` 渲染。

[English README](README.md) · [免责声明](DISCLAIMER.md) · [许可证](LICENSE)

## 当前状态

墨页还是早期开源项目，可以用于本地 Markdown 编辑，但还不是正式稳定版。

当前目标是先做好一个 macOS 文档型软件的基础体验：菜单栏、本地文件、可靠编辑、实时预览、图片、表格、导出和后续可演进的编辑器架构。

## 下载

请从 GitHub Releases 下载最新 macOS 版本：

<https://github.com/moye-source/moye-md/releases>

当前发布包格式：

```text
Moye-0.1.2-macOS.zip
```

当前版本暂未做 Apple Developer ID 签名和公证。macOS 首次打开时可能会提示“无法验证开发者”。请只运行你信任的构建包，并在使用前阅读 [免责声明](DISCLAIMER.md)。

如果墨页不是从 `/Applications` 启动，首次打开时会提示移动到“应用程序”文件夹，并从安装后的位置重新启动。

## 更新

在软件内使用 **帮助 > 检查更新...** 查看是否有新版本。

## 功能进度

- [x] 原生 macOS App
- [x] 默认中文界面，可切换英文
- [x] 本地 Markdown 源码编辑
- [x] 基于 AppKit `NSTextView` 的编辑器核心
- [x] Markdown 语法高亮
- [x] 分屏、仅编辑、仅预览模式
- [x] 编辑区和预览区可拖动调整宽度
- [x] 实时 HTML 预览
- [x] 编辑和预览按源码行同步滚动
- [x] 根据标题生成文档大纲
- [x] 文件夹侧栏，显示完整文件树
- [x] 文件名和文件内容搜索
- [x] 快速打开
- [x] 未保存修改状态
- [x] 撤销、重做、剪切、复制、粘贴、全选、查找、替换
- [x] 标准 macOS 菜单栏命令
- [x] 设置入口位于 App 菜单，快捷键 `Command-,`
- [x] 插入标题、目录、代码块、表格、任务列表、图片
- [x] 图片粘贴和拖拽到 `assets/` 文件夹
- [x] 表格行列增删辅助功能
- [x] HTML、PDF、无样式 HTML、PNG、Pandoc 导出入口
- [x] 支持 front matter、表格、任务列表、脚注、链接、本地图片和常见行内样式预览
- [x] MathJax 数学公式预览
- [x] Mermaid 图表预览
- [x] 专注模式、打字机模式、行号、自动配对
- [x] 词数、字符数、行数、阅读时间统计
- [x] 手动检查更新
- [ ] 签名和公证发布包
- [ ] App 内完整自动更新
- [ ] 离线内置 MathJax 和 Mermaid
- [ ] 引入 Markdown AST 管线
- [ ] Typora 式隐藏源码标记模式
- [ ] 更完整的 UI 自动化测试

## 系统要求

普通使用：

- macOS 13 或更高版本
- Pandoc 导入/导出需要本机安装 `pandoc`

开发：

- Xcode 和 macOS SDK
- 唯一支持的工程入口是 `NativeMarkdownEditor.xcodeproj`

旧的 Swift Package 原型入口已经删除，不要再使用 `swift run`、`swift build` 或 `.build/NativeMarkdownEditor.app` 验证真实编辑体验。

## 开发

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
./scripts/package-macos.sh 0.1.2
```

输出位置：

```text
dist/Moye-0.1.2-macOS.zip
```

## 发布流程

仓库已经配置 GitHub Actions。推送 `v` 开头的 tag 时，会自动打包 macOS App 并创建 GitHub Release。

```bash
git tag v0.1.2
git push origin v0.1.2
```

Release workflow 会生成并上传：

```text
Moye-0.1.2-macOS.zip
```

## 项目结构

```text
Sources/NativeMarkdownEditor/
  AppModels.swift                 共享模型和多语言文案
  ContentView.swift               主界面、侧栏、工具栏、状态栏
  DocumentStore.swift             文档状态、文件操作和菜单命令
  MarkdownEditorView.swift        基于 NSTextView 的 Markdown 编辑器
  MarkdownPreviewView.swift       基于 WKWebView 的实时预览
  MarkdownRenderer.swift          轻量 Markdown 到 HTML 渲染器
  MarkdownSyntaxHighlighter.swift 源码编辑器语法高亮
  NativeMarkdownEditorApp.swift   App 入口和菜单命令

Tests/NativeMarkdownEditorTests/
  MarkdownEditorInputTests.swift  编辑器、渲染、文件、更新和预览测试

docs/
  branding/                       名称和视觉方向
  typora-feature-parity.md        Typora 功能对齐记录
```

## 设计原则

- 优先遵循 macOS 原生桌面软件习惯。
- 菜单栏是核心命令入口。
- 侧栏只做文件树、大纲和搜索等导航。
- 文本输入、选区、撤销栈和中文输入法优先交给 AppKit 控制。
- 编辑器和 HTML 预览保持分层。
- 真正 Typora 式体验需要 Markdown 结构和选区映射，不用简单字符串替换冒充。

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
