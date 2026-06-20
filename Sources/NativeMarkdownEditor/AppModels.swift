import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }
}

struct LocalizedStrings {
    let language: AppLanguage

    var appName: String { text("墨页", "Moye") }
    var file: String { text("文件", "File") }
    var edit: String { text("编辑", "Edit") }
    var window: String { text("窗口", "Window") }
    var help: String { text("帮助", "Help") }
    var about: String { text("关于", "About") }
    var services: String { text("服务", "Services") }
    var hideApp: String { text("隐藏墨页", "Hide Moye") }
    var hideOthers: String { text("隐藏其他", "Hide Others") }
    var showAll: String { text("全部显示", "Show All") }
    var quitApp: String { text("退出墨页", "Quit Moye") }
    var languageLabel: String { text("语言", "Language") }
    var settings: String { text("设置...", "Settings...") }
    var settingsTitle: String { text("设置", "Settings") }
    var general: String { text("通用", "General") }
    var editor: String { text("编辑器", "Editor") }
    var assets: String { text("资源", "Assets") }
    var performance: String { text("性能", "Performance") }
    var done: String { text("完成", "Done") }
    var interfaceLanguage: String { text("界面语言", "Interface Language") }
    var chinese: String { "中文" }
    var english: String { "English" }
    var new: String { text("新建", "New") }
    var newDocument: String { text("新建文档", "New Document") }
    var newWorkspaceFile: String { text("新建文件...", "New File...") }
    var newWorkspaceFolder: String { text("新建文件夹...", "New Folder...") }
    var renameWorkspaceItem: String { text("重命名...", "Rename...") }
    var moveWorkspaceItemToTrash: String { text("移到废纸篓", "Move to Trash") }
    var open: String { text("打开", "Open") }
    var openFile: String { text("打开文件...", "Open...") }
    var openFolder: String { text("打开文件夹...", "Open Folder...") }
    var quickOpen: String { text("快速打开...", "Quick Open...") }
    var quickOpenTitle: String { text("快速打开", "Quick Open") }
    var quickOpenPlaceholder: String { text("输入文件名、路径或正文内容", "Type a file name, path, or content") }
    var save: String { text("保存", "Save") }
    var saveAs: String { text("另存为...", "Save As...") }
    var undo: String { text("撤销", "Undo") }
    var redo: String { text("重做", "Redo") }
    var cut: String { text("剪切", "Cut") }
    var copy: String { text("复制", "Copy") }
    var paste: String { text("粘贴", "Paste") }
    var selectAll: String { text("全选", "Select All") }
    var find: String { text("查找...", "Find...") }
    var replace: String { text("替换...", "Replace...") }
    var findNext: String { text("查找下一个", "Find Next") }
    var findPrevious: String { text("查找上一个", "Find Previous") }
    var view: String { text("显示", "View") }
    var viewMode: String { text("视图模式", "View Mode") }
    var theme: String { text("主题", "Theme") }
    var showSidebar: String { text("显示侧栏", "Show Sidebar") }
    var hideSidebar: String { text("隐藏侧栏", "Hide Sidebar") }
    var insert: String { text("插入", "Insert") }
    var heading: String { text("标题", "Heading") }
    var tableOfContents: String { text("目录", "Table of Contents") }
    var toc: String { text("目录", "TOC") }
    var code: String { text("代码", "Code") }
    var codeBlock: String { text("代码块", "Code Block") }
    var table: String { text("表格", "Table") }
    var tasks: String { text("任务", "Tasks") }
    var taskList: String { text("任务列表", "Task List") }
    var image: String { text("图片", "Image") }
    var imageMenu: String { text("图片...", "Image...") }
    var copyToAssets: String { text("复制到 assets", "Copy to assets") }
    var export: String { text("导出", "Export") }
    var exportHTML: String { text("导出 HTML...", "Export HTML...") }
    var exportHTMLWithoutStyles: String { text("导出无样式 HTML...", "Export HTML Without Styles...") }
    var exportPDF: String { text("导出 PDF...", "Export PDF...") }
    var exportImage: String { text("导出图片...", "Export Image...") }
    var exportWithPandoc: String { text("用 Pandoc 导出", "Export with Pandoc") }
    var importWithPandoc: String { text("用 Pandoc 导入...", "Import with Pandoc...") }
    var plain: String { text("纯文本", "Plain") }
    var writing: String { text("写作", "Writing") }
    var focus: String { text("专注", "Focus") }
    var typewriter: String { text("打字机", "Typewriter") }
    var lineNumbers: String { text("行号", "Line Numbers") }
    var autoPair: String { text("自动配对", "Auto Pair") }
    var files: String { text("文件", "Files") }
    var sidebarContent: String { text("侧栏内容", "Sidebar Content") }
    var openFolderHelp: String { text("打开文件夹", "Open Folder") }
    var searchFiles: String { text("搜索文件", "Search files") }
    var searchFilesAndContent: String { text("搜索文件或正文", "Search files or content") }
    var fileNameMatch: String { text("文件名", "File") }
    var contentMatch: String { text("正文", "Content") }
    var pathMatch: String { text("路径", "Path") }
    var openFolderPrompt: String { text("从菜单栏选择“文件 > 打开文件夹...”以浏览整个文件夹。", "Choose File > Open Folder... from the menu bar to browse a folder.") }
    var noMatchingFiles: String { text("没有匹配文件", "No matching files") }
    var noWorkspaceFolderForFileOperation: String { text("请先打开文件夹", "Open a folder first") }
    var outline: String { text("大纲", "Outline") }
    var noHeadings: String { text("没有标题", "No headings") }
    var words: String { text("词数", "Words") }
    var characters: String { text("字符", "Characters") }
    var lines: String { text("行数", "Lines") }
    var readTime: String { text("阅读时间", "Read Time") }
    var ready: String { text("就绪", "Ready") }
    var status: String { text("状态", "Status") }
    var untitledFileName: String { text("未命名.md", "Untitled.md") }
    var noFolder: String { text("未打开文件夹", "No Folder") }
    var unsavedChanges: String { text("未保存修改", "Unsaved changes") }
    var unsavedChangesVisible: String { text("有未保存修改", "Unsaved changes") }
    var unsavedPromptTitle: String { text("文档还没有保存", "The document has unsaved changes") }
    var unsavedPromptMessage: String { text("继续操作会丢失当前未保存的修改。", "Continuing will discard the current unsaved changes.") }
    var discardChanges: String { text("不保存继续", "Discard Changes") }
    var cancel: String { text("取消", "Cancel") }
    var saved: String { text("已保存", "Saved") }
    var enableFocusMode: String { text("启用专注模式", "Enable Focus Mode") }
    var disableFocusMode: String { text("关闭专注模式", "Disable Focus Mode") }
    var enableTypewriterMode: String { text("启用打字机模式", "Enable Typewriter Mode") }
    var disableTypewriterMode: String { text("关闭打字机模式", "Disable Typewriter Mode") }
    var showLineNumbers: String { text("显示行号", "Show Line Numbers") }
    var hideLineNumbers: String { text("隐藏行号", "Hide Line Numbers") }
    var enableAutoPair: String { text("启用自动配对", "Enable Auto Pair") }
    var disableAutoPair: String { text("关闭自动配对", "Disable Auto Pair") }
    var copyImagesToAssets: String { text("复制图片到 Assets", "Copy Images to Assets") }
    var keepOriginalImagePaths: String { text("保留原图片路径", "Keep Original Image Paths") }
    var performanceDiagnostics: String { text("性能诊断", "Performance Diagnostics") }
    var performanceDiagnosticsHelp: String {
        text(
            "默认开启，只记录最近的性能事件和计数信息，不记录正文内容。遇到卡顿时复制报告即可。",
            "Enabled by default. It records recent performance events and counters, not document body content. Copy the report when lag appears."
        )
    }
    var copyPerformanceReport: String { text("复制性能报告", "Copy Performance Report") }
    var resetPerformanceRecords: String { text("清空性能记录", "Clear Performance Records") }
    var copiedPerformanceReport: String { text("已复制性能报告", "Copied performance report") }
    var resetPerformanceRecordsDone: String { text("已清空性能记录", "Cleared performance records") }
    var enabledPerformanceDiagnostics: String { text("性能诊断已开启", "Performance diagnostics enabled") }
    var disabledPerformanceDiagnostics: String { text("性能诊断已关闭", "Performance diagnostics disabled") }
    var insertTable: String { text("插入表格", "Insert Table") }
    var addRowAbove: String { text("上方加一行", "Add Row Above") }
    var addRowBelow: String { text("下方加一行", "Add Row Below") }
    var deleteRow: String { text("删除所在行", "Delete Current Row") }
    var addColumnLeft: String { text("左侧加一列", "Add Column Left") }
    var addColumnRight: String { text("右侧加一列", "Add Column Right") }
    var deleteColumn: String { text("删除所在列", "Delete Current Column") }
    var formatTable: String { text("整理表格", "Format Table") }
    var codeTemplate: String { text("代码模板", "Code Template") }
    var minimize: String { text("最小化", "Minimize") }
    var zoom: String { text("缩放", "Zoom") }
    var bringAllToFront: String { text("全部置于前台", "Bring All to Front") }
    var markdownSyntaxReference: String { text("Markdown 语法参考", "Markdown Syntax Reference") }
    var checkForUpdates: String { text("检查更新...", "Check for Updates...") }
    var checkingForUpdates: String { text("正在检查更新...", "Checking for updates...") }
    var updateCheckFailedTitle: String { text("无法检查更新", "Unable to Check for Updates") }
    var updateCheckFailedMessage: String { text("请稍后重试，或前往 GitHub Releases 页面手动查看。", "Try again later, or open the GitHub Releases page manually.") }
    var updateAvailableTitle: String { text("发现新版本", "Update Available") }
    var noUpdateTitle: String { text("已经是最新版本", "You Are Up to Date") }
    var openDownloadPage: String { text("打开下载页面", "Open Download Page") }
    var helpTitle: String { text("墨页帮助", "Moye Help") }
    var helpMessage: String { text("通过菜单栏使用文件、编辑、视图、插入和导出命令。Markdown 语法参考会在浏览器中打开。", "Use the menu bar for file, edit, view, insert, and export commands. The Markdown syntax reference opens in your browser.") }
    var openMarkdownFileTitle: String { text("打开 Markdown 文件", "Open Markdown File") }
    var openFolderTitle: String { text("打开文件夹", "Open Folder") }
    var saveMarkdownFileTitle: String { text("保存 Markdown 文件", "Save Markdown File") }
    var insertImageTitle: String { text("插入图片", "Insert Image") }
    var unsupportedFileType: String { text("这个文件会显示在文件树中，但不会作为 Markdown 文本打开。", "This file type is listed but not opened as Markdown text.") }
    var invalidWorkspaceItemName: String { text("名称不能为空，也不能包含 /。", "Names cannot be empty or contain /.") }
    var workspaceItemAlreadyExists: String { text("同名项目已经存在。", "An item with that name already exists.") }
    var newFilePromptTitle: String { text("新建文件", "New File") }
    var newFilePromptMessage: String { text("输入文件名；没有扩展名时会自动使用 .md。", "Enter a file name. .md is added when no extension is provided.") }
    var newFolderPromptTitle: String { text("新建文件夹", "New Folder") }
    var newFolderPromptMessage: String { text("输入文件夹名称。", "Enter a folder name.") }
    var renamePromptTitle: String { text("重命名", "Rename") }
    var renamePromptMessage: String { text("输入新名称。", "Enter a new name.") }
    var deletePromptTitle: String { text("移到废纸篓", "Move to Trash") }
    var deletePromptMessage: String { text("这个项目会移到废纸篓，可以从 Finder 恢复。", "This item will be moved to Trash and can be restored from Finder.") }
    var chooseTableBodyRow: String { text("请选择表格正文行", "Select a table body row") }
    var keepOneColumn: String { text("至少保留一列", "Keep at least one column") }
    var cursorNotInTable: String { text("光标不在 Markdown 表格内", "The cursor is not inside a Markdown table") }
    var insertedMarkdownBlock: String { text("已插入 Markdown 块", "Inserted Markdown block") }
    var noSupportedImageFiles: String { text("没有找到支持的图片文件", "No supported image files found") }
    var noDocumentWindow: String { text("没有可关闭的文档窗口", "No document window is available") }

    func updateAvailableMessage(current: String, latest: String, assetName: String?) -> String {
        let assetLine = assetName.map {
            text("可下载文件：\($0)", "Download asset: \($0)")
        } ?? text("可以前往 GitHub Releases 下载最新版本。", "Open GitHub Releases to download the latest version.")

        return text(
            "当前版本：\(current)\n最新版本：\(latest)\n\(assetLine)",
            "Current version: \(current)\nLatest version: \(latest)\n\(assetLine)"
        )
    }

    func noUpdateMessage(current: String) -> String {
        text(
            "当前版本 \(current) 已经是 GitHub Releases 上的最新版本。",
            "Version \(current) is the latest version available on GitHub Releases."
        )
    }

    func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .chinese:
            chinese
        case .english:
            english
        }
    }

    func viewModeTitle(_ mode: EditorViewMode) -> String {
        switch mode {
        case .split:
            text("分屏", "Split")
        case .editor:
            text("编辑", "Editor")
        case .preview:
            text("预览", "Preview")
        }
    }

    func sidebarPanelTitle(_ panel: SidebarPanel) -> String {
        switch panel {
        case .files:
            files
        case .outline:
            outline
        }
    }

    func sidebarPanelChanged(_ panel: SidebarPanel) -> String {
        text("侧栏：\(sidebarPanelTitle(panel))", "Sidebar: \(sidebarPanelTitle(panel))")
    }

    func previewThemeTitle(_ theme: PreviewTheme) -> String {
        switch theme {
        case .system:
            text("跟随系统", "System")
        case .light:
            text("浅色", "Light")
        case .dark:
            text("深色", "Dark")
        case .sepia:
            text("暖色", "Sepia")
        }
    }

    func pandocFormatTitle(_ format: PandocExportFormat) -> String {
        switch format {
        case .docx:
            text("Word (.docx)", "Word (.docx)")
        case .rtf:
            "RTF"
        case .epub:
            "EPUB"
        case .latex:
            "LaTeX"
        }
    }

    func minutes(_ value: Int) -> String {
        text("\(value) 分钟", "\(value)m")
    }

    func themeMenuTitle(_ theme: PreviewTheme) -> String {
        text("\(previewThemeTitle(theme))主题", "\(previewThemeTitle(theme)) Theme")
    }

    func languageChanged(to language: AppLanguage) -> String {
        switch language {
        case .chinese:
            "界面语言已切换为中文"
        case .english:
            "Language switched to English"
        }
    }

    func viewModeChanged(_ mode: EditorViewMode) -> String {
        text("视图模式：\(viewModeTitle(mode))", "View mode: \(viewModeTitle(mode))")
    }

    func previewThemeChanged(_ theme: PreviewTheme) -> String {
        text("预览主题：\(previewThemeTitle(theme))", "Preview theme: \(previewThemeTitle(theme))")
    }

    func openedFolder(_ name: String) -> String {
        text("已打开文件夹 \(name)", "Opened folder \(name)")
    }

    func openedFile(_ name: String) -> String {
        text("已打开 \(name)", "Opened \(name)")
    }

    func savedFile(_ name: String) -> String {
        text("已保存 \(name)", "Saved \(name)")
    }

    func createdFile(_ name: String) -> String {
        text("已新建文件 \(name)", "Created file \(name)")
    }

    func createdFolder(_ name: String) -> String {
        text("已新建文件夹 \(name)", "Created folder \(name)")
    }

    func renamedItem(_ name: String) -> String {
        text("已重命名为 \(name)", "Renamed to \(name)")
    }

    func movedItemToTrash(_ name: String) -> String {
        text("已移到废纸篓：\(name)", "Moved to Trash: \(name)")
    }

    func folderStatus(_ path: String) -> String {
        text("文件夹：\(path)", "Folder: \(path)")
    }

    func jumpTo(_ title: String) -> String {
        text("跳转到 \(title)", "Jumped to \(title)")
    }

    func insertedImages(_ count: Int) -> String {
        text("已插入 \(count) 张图片", "Inserted \(count) image(s)")
    }

    private func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }
}

enum SidebarPanel: String, CaseIterable, Identifiable {
    case files
    case outline

    var id: String { rawValue }
}

enum EditorViewMode: String, CaseIterable, Identifiable {
    case split
    case editor
    case preview

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .split:
            "rectangle.split.2x1"
        case .editor:
            "square.and.pencil"
        case .preview:
            "doc.richtext"
        }
    }
}

enum PreviewTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case sepia

    var id: String { rawValue }

    var cssClass: String {
        "theme-\(rawValue)"
    }
}

struct OutlineItem: Identifiable, Equatable {
    let id: String
    let level: Int
    let title: String
    let location: Int
    let line: Int
}

struct DocumentStatistics: Equatable {
    let wordCount: Int
    let characterCount: Int
    let lineCount: Int

    var readingMinutes: Int {
        max(1, Int(ceil(Double(wordCount) / 220.0)))
    }

    static let empty = DocumentStatistics(wordCount: 0, characterCount: 0, lineCount: 1)

    init(markdown: String) {
        var words = 0
        var characters = 0
        var lines = 1
        var isInsideWord = false

        for character in markdown {
            characters += 1
            if character == "\n" {
                lines += 1
            }

            if character.isWhitespace || character.isNewline {
                isInsideWord = false
            } else if !isInsideWord {
                words += 1
                isInsideWord = true
            }
        }

        wordCount = words
        characterCount = characters
        lineCount = lines
    }

    init(wordCount: Int, characterCount: Int, lineCount: Int) {
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.lineCount = lineCount
    }
}

struct WorkspaceFile: Identifiable, Equatable {
    let id: String
    let url: URL
    let relativePath: String
    let isDirectory: Bool
    let isTextLike: Bool

    var displayName: String {
        url.lastPathComponent
    }
}

struct WorkspaceTreeNode: Identifiable, Equatable {
    let file: WorkspaceFile
    let children: [WorkspaceTreeNode]

    var id: String {
        file.id
    }
}

struct WorkspaceTreeRow: Identifiable, Equatable {
    let file: WorkspaceFile
    let depth: Int

    var id: String {
        file.id
    }
}

enum WorkspaceMatchKind: Equatable {
    case path
    case fileName
    case content
}

struct WorkspaceSearchResult: Identifiable, Equatable {
    let file: WorkspaceFile
    let matchKind: WorkspaceMatchKind
    let snippet: String?

    var id: String {
        "\(file.id)-\(matchKind)-\(snippet ?? "")"
    }
}

struct SourceLineScrollTarget: Equatable {
    let line: Int
    let revision: Int
    let location: Int?
    let anchorID: String?

    init(line: Int, revision: Int, location: Int? = nil, anchorID: String? = nil) {
        self.line = line
        self.revision = revision
        self.location = location
        self.anchorID = anchorID
    }
}

struct CodeTemplate: Identifiable {
    let id: String
    let title: String
    let language: String
    let systemImage: String
    let snippet: String

    static let common: [CodeTemplate] = [
        CodeTemplate(
            id: "swift",
            title: "Swift",
            language: "swift",
            systemImage: "curlybraces",
            snippet: #"print("Hello, Moye")"#
        ),
        CodeTemplate(
            id: "typescript",
            title: "TypeScript",
            language: "ts",
            systemImage: "curlybraces",
            snippet: """
            type Note = {
              title: string
              body: string
            }
            """
        ),
        CodeTemplate(
            id: "python",
            title: "Python",
            language: "python",
            systemImage: "terminal",
            snippet: """
            from pathlib import Path

            print(Path.cwd())
            """
        ),
        CodeTemplate(
            id: "bash",
            title: "Shell",
            language: "bash",
            systemImage: "terminal.fill",
            snippet: """
            set -euo pipefail

            echo "deploy"
            """
        ),
        CodeTemplate(
            id: "json",
            title: "JSON",
            language: "json",
            systemImage: "curlybraces.square",
            snippet: """
            {
              "name": "moye",
              "private": true
            }
            """
        ),
        CodeTemplate(
            id: "yaml",
            title: "YAML",
            language: "yaml",
            systemImage: "list.bullet.rectangle",
            snippet: """
            service:
              name: moye
              port: 8080
            """
        ),
        CodeTemplate(
            id: "toml",
            title: "TOML",
            language: "toml",
            systemImage: "slider.horizontal.3",
            snippet: """
            [server]
            host = "127.0.0.1"
            port = 8080
            """
        ),
        CodeTemplate(
            id: "nginx",
            title: "Nginx",
            language: "nginx",
            systemImage: "network",
            snippet: """
            server {
              listen 80;
              server_name example.com;

              location / {
                proxy_pass http://127.0.0.1:8080;
              }
            }
            """
        ),
        CodeTemplate(
            id: "dockerfile",
            title: "Dockerfile",
            language: "dockerfile",
            systemImage: "shippingbox",
            snippet: """
            FROM nginx:alpine
            COPY ./public /usr/share/nginx/html
            """
        ),
        CodeTemplate(
            id: "kubernetes",
            title: "Kubernetes",
            language: "yaml",
            systemImage: "hexagon",
            snippet: """
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: moye
            spec:
              replicas: 2
            """
        ),
        CodeTemplate(
            id: "sql",
            title: "SQL",
            language: "sql",
            systemImage: "cylinder.split.1x2",
            snippet: """
            select id, title, updated_at
            from documents
            order by updated_at desc;
            """
        ),
    ]
}

enum PandocExportFormat: String, CaseIterable, Identifiable {
    case docx
    case rtf
    case epub
    case latex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docx:
            "Word (.docx)"
        case .rtf:
            "RTF"
        case .epub:
            "EPUB"
        case .latex:
            "LaTeX"
        }
    }

    var fileExtension: String {
        switch self {
        case .docx:
            "docx"
        case .rtf:
            "rtf"
        case .epub:
            "epub"
        case .latex:
            "tex"
        }
    }
}
