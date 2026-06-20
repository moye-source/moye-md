import AppKit
import SwiftUI

@main
struct NativeMarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var documentStore = DocumentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentStore)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.documentStore = documentStore
                }
        }
        .commands {
            NativeMarkdownEditorCommands(documentStore: documentStore)
        }

        Settings {
            SettingsView()
                .environmentObject(documentStore)
        }
    }
}

private struct NativeMarkdownEditorCommands: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        AppCommandSet(documentStore: documentStore)
        EditCommandSet(documentStore: documentStore)
        FileCommandSet(documentStore: documentStore)
        ViewCommandSet(documentStore: documentStore)
        InsertCommandSet(documentStore: documentStore)
        WindowHelpCommandSet(documentStore: documentStore)
    }
}

private struct AppCommandSet: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(documentStore.strings.settings) {
                NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

private struct EditCommandSet: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(documentStore.strings.undo) {
                documentStore.undoEditing()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!documentStore.canUndo)

            Button(documentStore.strings.redo) {
                documentStore.redoEditing()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!documentStore.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button(documentStore.strings.cut) {
                documentStore.cutSelection()
            }
            .keyboardShortcut("x", modifiers: .command)

            Button(documentStore.strings.copy) {
                documentStore.copySelection()
            }
            .keyboardShortcut("c", modifiers: .command)

            Button(documentStore.strings.paste) {
                documentStore.pasteFromPasteboard()
            }
            .keyboardShortcut("v", modifiers: .command)
        }

        CommandGroup(replacing: .textEditing) {
            Button(documentStore.strings.selectAll) {
                documentStore.selectAllText()
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button(documentStore.strings.find) {
                documentStore.showFindPanel()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(documentStore.strings.replace) {
                documentStore.showReplacePanel()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button(documentStore.strings.findNext) {
                documentStore.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)

            Button(documentStore.strings.findPrevious) {
                documentStore.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

private struct FileCommandSet: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(documentStore.strings.newDocument) {
                documentStore.newDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(documentStore.strings.newWorkspaceFile) {
                documentStore.createWorkspaceFileInSelectedLocation()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(documentStore.workspaceURL == nil)

            Button(documentStore.strings.newWorkspaceFolder) {
                documentStore.createWorkspaceFolderInSelectedLocation()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(documentStore.workspaceURL == nil)
        }

        CommandGroup(after: .newItem) {
            Button(documentStore.strings.openFile) {
                documentStore.openDocument()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(documentStore.strings.openFolder) {
                documentStore.openFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button(documentStore.strings.quickOpen) {
                documentStore.showQuickOpen()
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button(documentStore.strings.renameWorkspaceItem) {
                documentStore.renameSelectedWorkspaceItem()
            }
            .disabled(documentStore.selectedWorkspaceFile == nil)

            Button(documentStore.strings.moveWorkspaceItemToTrash) {
                documentStore.moveSelectedWorkspaceItemToTrash()
            }
            .disabled(documentStore.selectedWorkspaceFile == nil)

            Divider()

            Button(documentStore.strings.importWithPandoc) {
                documentStore.importWithPandoc()
            }

            Button(documentStore.strings.save) {
                documentStore.saveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(documentStore.strings.saveAs) {
                documentStore.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(documentStore.strings.exportHTML) {
                documentStore.exportHTML()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            Button(documentStore.strings.exportHTMLWithoutStyles) {
                documentStore.exportHTMLWithoutStyles()
            }

            Button(documentStore.strings.exportPDF) {
                documentStore.exportPDF()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button(documentStore.strings.exportImage) {
                documentStore.exportImage()
            }

            Menu(documentStore.strings.exportWithPandoc) {
                ForEach(PandocExportFormat.allCases) { format in
                    Button(documentStore.strings.pandocFormatTitle(format)) {
                        documentStore.exportWithPandoc(format)
                    }
                }
            }
        }
    }
}

private struct ViewCommandSet: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(documentStore.isSidebarVisible ? documentStore.strings.hideSidebar : documentStore.strings.showSidebar) {
                documentStore.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        CommandGroup(after: .sidebar) {
            Divider()

            ForEach(EditorViewMode.allCases) { mode in
                Button(documentStore.strings.viewModeTitle(mode)) {
                    documentStore.setViewMode(mode)
                }
                .keyboardShortcut(viewModeShortcut(for: mode), modifiers: [.command, .option])
            }

            Divider()

            ForEach(PreviewTheme.allCases) { theme in
                Button(documentStore.strings.themeMenuTitle(theme)) {
                    documentStore.setPreviewTheme(theme)
                }
            }

            Divider()

            Button(documentStore.focusModeEnabled ? documentStore.strings.disableFocusMode : documentStore.strings.enableFocusMode) {
                documentStore.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button(documentStore.typewriterModeEnabled ? documentStore.strings.disableTypewriterMode : documentStore.strings.enableTypewriterMode) {
                documentStore.toggleTypewriterMode()
            }
            .keyboardShortcut("y", modifiers: [.command, .option])

            Button(documentStore.lineNumbersEnabled ? documentStore.strings.hideLineNumbers : documentStore.strings.showLineNumbers) {
                documentStore.toggleLineNumbers()
            }

            Button(documentStore.autoPairEnabled ? documentStore.strings.disableAutoPair : documentStore.strings.enableAutoPair) {
                documentStore.toggleAutoPair()
            }

            Button(documentStore.copyImagesToAssetFolder ? documentStore.strings.keepOriginalImagePaths : documentStore.strings.copyImagesToAssets) {
                documentStore.toggleCopyImagesToAssetFolder()
            }
        }
    }

    private func viewModeShortcut(for mode: EditorViewMode) -> KeyEquivalent {
        switch mode {
        case .split:
            "1"
        case .editor:
            "2"
        case .preview:
            "3"
        }
    }
}

private struct InsertCommandSet: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        CommandMenu(documentStore.strings.insert) {
            Button(documentStore.strings.heading) {
                documentStore.insertHeading()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button(documentStore.strings.tableOfContents) {
                documentStore.insertTableOfContents()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Menu(documentStore.strings.codeBlock) {
                ForEach(CodeTemplate.common) { template in
                    Button(template.title) {
                        documentStore.insertCodeTemplate(template)
                    }
                }
            }

            Menu(documentStore.strings.table) {
                Button(documentStore.strings.insertTable) {
                    documentStore.insertTable()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Divider()

                Button(documentStore.strings.addRowAbove) {
                    documentStore.insertTableRowAbove()
                }

                Button(documentStore.strings.addRowBelow) {
                    documentStore.insertTableRowBelow()
                }

                Button(documentStore.strings.deleteRow) {
                    documentStore.deleteCurrentTableRows()
                }

                Divider()

                Button(documentStore.strings.addColumnLeft) {
                    documentStore.insertTableColumnLeft()
                }

                Button(documentStore.strings.addColumnRight) {
                    documentStore.insertTableColumnRight()
                }

                Button(documentStore.strings.deleteColumn) {
                    documentStore.deleteCurrentTableColumn()
                }

                Divider()

                Button(documentStore.strings.formatTable) {
                    documentStore.formatCurrentTable()
                }
            }

            Button(documentStore.strings.taskList) {
                documentStore.insertTaskList()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button(documentStore.strings.imageMenu) {
                documentStore.insertImage()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

private struct WindowHelpCommandSet: Commands {
    @ObservedObject var documentStore: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .windowSize) {
            Button(documentStore.strings.minimize) {
                NSApplication.shared.keyWindow?.performMiniaturize(nil)
            }
            .keyboardShortcut("m", modifiers: .command)

            Button(documentStore.strings.zoom) {
                NSApplication.shared.keyWindow?.performZoom(nil)
            }
        }

        CommandGroup(replacing: .windowArrangement) {
            Button(documentStore.strings.bringAllToFront) {
                NSApplication.shared.arrangeInFront(nil)
            }
        }

        CommandGroup(replacing: .help) {
            Button(documentStore.strings.help) {
                documentStore.showHelp()
            }

            Button(documentStore.strings.markdownSyntaxReference) {
                documentStore.openMarkdownSyntaxReference()
            }

            Divider()

            Button(documentStore.strings.checkForUpdates) {
                documentStore.checkForUpdates()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var documentStore: DocumentStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.identifier = NSUserInterfaceItemIdentifier("editorWindow")
                window.delegate = self
                window.makeKeyAndOrderFront(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainMenuLocalizer.localize(language: .chinese)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            MainMenuLocalizer.localize(language: .chinese)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            MainMenuLocalizer.localize(language: .chinese)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard documentStore?.confirmDiscardUnsavedChangesIfNeeded() == false else {
            return .terminateNow
        }
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.identifier?.rawValue == "editorWindow" else {
            return true
        }
        return documentStore?.confirmDiscardUnsavedChangesIfNeeded() ?? true
    }
}

enum MainMenuLocalizer {
    static func localizeChinese() {
        localize(language: .chinese)
    }

    static func localize(language: AppLanguage) {
        guard let mainMenu = NSApplication.shared.mainMenu else {
            return
        }

        let strings = LocalizedStrings(language: language)
        let appName = strings.appName
        let replacements: [String: String] = [
            "NativeMarkdownEditor": appName,
            "Native Markdown Editor": appName,
            "Moye": appName,
            "墨页": appName,
            "File": strings.file,
            "文件": strings.file,
            "Edit": strings.edit,
            "编辑": strings.edit,
            "View": strings.view,
            "视图": strings.view,
            "Window": strings.window,
            "窗口": strings.window,
            "Help": strings.help,
            "帮助": strings.help,
            "Services": strings.services,
            "服务": strings.services,
            "Hide Native Markdown Editor": strings.hideApp,
            "Hide NativeMarkdownEditor": strings.hideApp,
            "Hide Moye": strings.hideApp,
            "隐藏墨页": strings.hideApp,
            "Hide Others": strings.hideOthers,
            "隐藏其他": strings.hideOthers,
            "Show All": strings.showAll,
            "全部显示": strings.showAll,
            "Quit Native Markdown Editor": strings.quitApp,
            "Quit NativeMarkdownEditor": strings.quitApp,
            "Quit Moye": strings.quitApp,
            "退出墨页": strings.quitApp,
            "About Native Markdown Editor": "\(strings.about) \(appName)",
            "About NativeMarkdownEditor": "\(strings.about) \(appName)",
            "About Moye": "\(strings.about) \(appName)",
            "关于墨页": "\(strings.about) \(appName)",
            "Settings...": strings.settings,
            "设置...": strings.settings,
            "Replace...": strings.replace,
            "替换...": strings.replace,
            "New File...": strings.newWorkspaceFile,
            "新建文件...": strings.newWorkspaceFile,
            "New Folder...": strings.newWorkspaceFolder,
            "新建文件夹...": strings.newWorkspaceFolder,
            "Rename...": strings.renameWorkspaceItem,
            "重命名...": strings.renameWorkspaceItem,
            "Move to Trash": strings.moveWorkspaceItemToTrash,
            "移到废纸篓": strings.moveWorkspaceItemToTrash,
            "Quick Open...": strings.quickOpen,
            "快速打开...": strings.quickOpen,
            "Minimize": strings.minimize,
            "最小化": strings.minimize,
            "Zoom": strings.zoom,
            "缩放": strings.zoom,
            "Bring All to Front": strings.bringAllToFront,
            "全部置于前台": strings.bringAllToFront,
        ]

        func apply(to menu: NSMenu) {
            for item in menu.items {
                if let replacement = replacements[item.title] {
                    item.title = replacement
                }
                if let submenu = item.submenu {
                    if let replacement = replacements[submenu.title] {
                        submenu.title = replacement
                    }
                    apply(to: submenu)
                }
            }
        }

        func setTopLevel(_ item: NSMenuItem, title: String) {
            item.title = title
            item.submenu?.title = title
        }

        for (index, item) in mainMenu.items.enumerated() {
            switch index {
            case 0:
                setTopLevel(item, title: appName)
            case 1:
                setTopLevel(item, title: strings.file)
            case 2:
                setTopLevel(item, title: strings.edit)
            case 3:
                setTopLevel(item, title: strings.view)
            default:
                if ["Window", "窗口"].contains(item.title) {
                    setTopLevel(item, title: strings.window)
                } else if ["Help", "帮助"].contains(item.title) {
                    setTopLevel(item, title: strings.help)
                }
            }
        }

        apply(to: mainMenu)
    }
}
