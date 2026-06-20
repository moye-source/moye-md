import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var markdown: String {
        willSet {
            registerUndoSnapshot(markdown, replacingWith: newValue)
        }
        didSet {
            outline = Self.buildOutline(from: markdown)
        }
    }
    @Published var selectedRange: NSRange
    @Published var viewMode: EditorViewMode
    @Published var isSidebarVisible: Bool
    @Published var sidebarPanel: SidebarPanel
    @Published var previewTheme: PreviewTheme
    @Published var focusModeEnabled: Bool
    @Published var typewriterModeEnabled: Bool
    @Published var lineNumbersEnabled: Bool
    @Published var autoPairEnabled: Bool
    @Published var copyImagesToAssetFolder: Bool
    @Published var language: AppLanguage
    @Published var workspaceURL: URL?
    @Published var fileSearchQuery: String
    @Published var expandedWorkspaceDirectories: Set<String>
    @Published var selectedWorkspaceFileID: String?
    @Published var isQuickOpenPresented: Bool
    @Published var quickOpenQuery: String
    @Published private(set) var fileURL: URL?
    @Published private(set) var statusMessage: String
    @Published private(set) var outline: [OutlineItem]
    @Published private(set) var editorNavigationTarget: SourceLineScrollTarget?

    private var lastSavedSnapshot: String
    private var activePDFExporter: MarkdownPDFExporter?
    private var activeImageExporter: MarkdownImageExporter?
    private var undoStack: [String]
    private var redoStack: [String]
    private var isApplyingHistory: Bool
    private var navigationRevision: Int

    init() {
        let initialLanguage = AppLanguage.chinese
        let sample = Self.defaultDocument(for: initialLanguage)
        markdown = sample
        selectedRange = NSRange(location: (sample as NSString).length, length: 0)
        viewMode = .split
        isSidebarVisible = true
        sidebarPanel = .files
        previewTheme = .system
        focusModeEnabled = false
        typewriterModeEnabled = false
        lineNumbersEnabled = false
        autoPairEnabled = true
        copyImagesToAssetFolder = true
        language = initialLanguage
        workspaceURL = nil
        fileSearchQuery = ""
        expandedWorkspaceDirectories = []
        selectedWorkspaceFileID = nil
        isQuickOpenPresented = false
        quickOpenQuery = ""
        outline = Self.buildOutline(from: sample)
        editorNavigationTarget = nil
        lastSavedSnapshot = sample
        statusMessage = LocalizedStrings(language: initialLanguage).ready
        undoStack = []
        redoStack = []
        isApplyingHistory = false
        navigationRevision = 0
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var strings: LocalizedStrings {
        LocalizedStrings(language: language)
    }

    var displayName: String {
        fileURL?.lastPathComponent ?? strings.untitledFileName
    }

    var dirtyIndicator: String {
        isDirty ? strings.unsavedChangesVisible : strings.saved
    }

    var isDirty: Bool {
        markdown != lastSavedSnapshot
    }

    var wordCount: Int {
        markdown
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    var characterCount: Int {
        markdown.count
    }

    var lineCount: Int {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var readingMinutes: Int {
        max(1, Int(ceil(Double(wordCount) / 220.0)))
    }

    private static func buildOutline(from markdown: String) -> [OutlineItem] {
        let nsMarkdown = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsMarkdown.length)
        var items: [OutlineItem] = []
        var lineNumber = 1

        nsMarkdown.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            let currentLine = lineNumber
            lineNumber += 1
            let line = nsMarkdown.substring(with: substringRange).trimmingCharacters(in: .whitespaces)
            let markerCount = line.prefix { $0 == "#" }.count
            guard (1...6).contains(markerCount) else {
                return
            }

            let index = line.index(line.startIndex, offsetBy: markerCount)
            guard index < line.endIndex, line[index] == " " else {
                return
            }

            let title = line[index...].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else {
                return
            }

            items.append(OutlineItem(
                id: "\(substringRange.location)-\(markerCount)-\(title)",
                level: markerCount,
                title: title,
                location: substringRange.location,
                line: currentLine
            ))
        }

        return items
    }

    var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var workspaceTitle: String {
        workspaceURL?.lastPathComponent ?? strings.noFolder
    }

    var workspaceFiles: [WorkspaceFile] {
        guard let workspaceURL else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [WorkspaceFile] = []
        for case let url as URL in enumerator {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
                continue
            }
            let isDirectory = resourceValues.isDirectory == true
            let isRegularFile = resourceValues.isRegularFile == true
            guard isDirectory || isRegularFile else { continue }

            let relativePath = url.relativePath(from: workspaceURL) ?? url.lastPathComponent
            files.append(WorkspaceFile(
                id: url.path,
                url: url,
                relativePath: relativePath,
                isDirectory: isDirectory,
                isTextLike: !isDirectory && Self.isTextLikeURL(url)
            ))
        }

        return files.sorted(by: Self.sortWorkspaceFiles)
    }

    var workspaceTree: [WorkspaceTreeNode] {
        let grouped = Dictionary(grouping: workspaceFiles) { file in
            Self.parentPath(for: file.relativePath)
        }

        func makeNodes(parentPath: String) -> [WorkspaceTreeNode] {
            (grouped[parentPath] ?? [])
                .sorted(by: Self.sortWorkspaceFiles)
                .map { file in
                    WorkspaceTreeNode(
                        file: file,
                        children: file.isDirectory ? makeNodes(parentPath: file.relativePath) : []
                    )
                }
        }

        return makeNodes(parentPath: "")
    }

    var visibleWorkspaceTreeRows: [WorkspaceTreeRow] {
        var rows: [WorkspaceTreeRow] = []

        func append(nodes: [WorkspaceTreeNode], depth: Int) {
            for node in nodes {
                rows.append(WorkspaceTreeRow(file: node.file, depth: depth))
                if node.file.isDirectory, isWorkspaceDirectoryExpanded(node.file) {
                    append(nodes: node.children, depth: depth + 1)
                }
            }
        }

        append(nodes: workspaceTree, depth: 0)
        return rows
    }

    var filteredWorkspaceFiles: [WorkspaceFile] {
        workspaceSearchResults.map(\.file)
    }

    var workspaceSearchResults: [WorkspaceSearchResult] {
        workspaceSearchResults(
            matching: fileSearchQuery,
            includeDirectories: true,
            includeUnsupportedFiles: true
        )
    }

    var quickOpenResults: [WorkspaceSearchResult] {
        workspaceSearchResults(
            matching: quickOpenQuery,
            includeDirectories: false,
            includeUnsupportedFiles: false
        )
    }

    var selectedWorkspaceFile: WorkspaceFile? {
        guard let selectedWorkspaceFileID else {
            return nil
        }
        return workspaceFiles.first { $0.id == selectedWorkspaceFileID }
    }

    func newDocument() {
        guard confirmDiscardUnsavedChangesIfNeeded() else {
            return
        }
        markdown = Self.defaultDocument(for: language)
        fileURL = nil
        selectedRange = NSRange(location: (markdown as NSString).length, length: 0)
        lastSavedSnapshot = markdown
        statusMessage = strings.newDocument
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else {
            return
        }
        self.language = language
        statusMessage = strings.languageChanged(to: language)
        localizeMainMenu()
    }

    func openDocument() {
        guard confirmDiscardUnsavedChangesIfNeeded() else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = strings.openMarkdownFileTitle
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.markdownContentTypes

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            let contents = try String(contentsOf: selectedURL, encoding: .utf8)
            load(contents: contents, from: selectedURL)
            workspaceURL = selectedURL.deletingLastPathComponent()
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.title = strings.openFolderTitle
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        workspaceURL = selectedURL
        fileSearchQuery = ""
        expandedWorkspaceDirectories.removeAll()
        selectedWorkspaceFileID = nil
        quickOpenQuery = ""
        statusMessage = strings.openedFolder(selectedURL.lastPathComponent)
    }

    func openWorkspaceFile(_ workspaceFile: WorkspaceFile) {
        selectWorkspaceFile(workspaceFile)
        if workspaceFile.isDirectory {
            toggleWorkspaceDirectory(workspaceFile)
            statusMessage = strings.folderStatus(workspaceFile.relativePath)
            return
        }

        guard workspaceFile.isTextLike else {
            statusMessage = strings.unsupportedFileType
            return
        }

        guard confirmDiscardUnsavedChangesIfNeeded() else {
            return
        }

        do {
            let contents = try String(contentsOf: workspaceFile.url, encoding: .utf8)
            load(contents: contents, from: workspaceFile.url)
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
    }

    func selectWorkspaceFile(_ workspaceFile: WorkspaceFile) {
        selectedWorkspaceFileID = workspaceFile.id
    }

    func toggleWorkspaceDirectory(_ workspaceFile: WorkspaceFile) {
        guard workspaceFile.isDirectory else {
            return
        }
        if expandedWorkspaceDirectories.contains(workspaceFile.id) {
            expandedWorkspaceDirectories.remove(workspaceFile.id)
        } else {
            expandedWorkspaceDirectories.insert(workspaceFile.id)
        }
    }

    func isWorkspaceDirectoryExpanded(_ workspaceFile: WorkspaceFile) -> Bool {
        expandedWorkspaceDirectories.contains(workspaceFile.id)
    }

    func showQuickOpen() {
        quickOpenQuery = ""
        isQuickOpenPresented = true
    }

    func dismissQuickOpen() {
        isQuickOpenPresented = false
    }

    func openQuickOpenResult(_ result: WorkspaceSearchResult) {
        isQuickOpenPresented = false
        openWorkspaceFile(result.file)
    }

    func createWorkspaceFileInSelectedLocation() {
        createWorkspaceFile(in: selectedWorkspaceFile)
    }

    func createWorkspaceFolderInSelectedLocation() {
        createWorkspaceFolder(in: selectedWorkspaceFile)
    }

    func createWorkspaceFile(in targetItem: WorkspaceFile?) {
        guard let name = promptForWorkspaceName(
            title: strings.newFilePromptTitle,
            message: strings.newFilePromptMessage,
            defaultValue: "Untitled.md"
        ) else {
            return
        }
        createWorkspaceFile(named: name, in: targetItem)
    }

    @discardableResult
    func createWorkspaceFile(
        named rawName: String,
        in targetItem: WorkspaceFile?,
        openCreatedFile: Bool = true
    ) -> URL? {
        guard let directoryURL = targetDirectoryURL(for: targetItem) else {
            return nil
        }
        guard var name = normalizedWorkspaceItemName(rawName) else {
            statusMessage = strings.invalidWorkspaceItemName
            return nil
        }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            name += ".md"
        }

        let destinationURL = directoryURL.appendingPathComponent(name, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            statusMessage = strings.workspaceItemAlreadyExists
            return nil
        }

        if openCreatedFile, !confirmDiscardUnsavedChangesIfNeeded() {
            return nil
        }

        do {
            try "".write(to: destinationURL, atomically: true, encoding: .utf8)
            expandWorkspaceDirectory(for: directoryURL)
            if let file = workspaceFile(for: destinationURL) {
                selectedWorkspaceFileID = file.id
            }
            statusMessage = strings.createdFile(name)
            if openCreatedFile {
                load(contents: "", from: destinationURL)
            }
            return destinationURL
        } catch {
            statusMessage = "Create file failed: \(error.localizedDescription)"
            return nil
        }
    }

    func createWorkspaceFolder(in targetItem: WorkspaceFile?) {
        guard let name = promptForWorkspaceName(
            title: strings.newFolderPromptTitle,
            message: strings.newFolderPromptMessage,
            defaultValue: "New Folder"
        ) else {
            return
        }
        createWorkspaceFolder(named: name, in: targetItem)
    }

    @discardableResult
    func createWorkspaceFolder(named rawName: String, in targetItem: WorkspaceFile?) -> URL? {
        guard let directoryURL = targetDirectoryURL(for: targetItem) else {
            return nil
        }
        guard let name = normalizedWorkspaceItemName(rawName) else {
            statusMessage = strings.invalidWorkspaceItemName
            return nil
        }

        let destinationURL = directoryURL.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            statusMessage = strings.workspaceItemAlreadyExists
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)
            expandWorkspaceDirectory(for: directoryURL)
            if let file = workspaceFile(for: destinationURL) {
                selectedWorkspaceFileID = file.id
                expandedWorkspaceDirectories.insert(file.id)
            }
            statusMessage = strings.createdFolder(name)
            return destinationURL
        } catch {
            statusMessage = "Create folder failed: \(error.localizedDescription)"
            return nil
        }
    }

    func renameSelectedWorkspaceItem() {
        guard let selectedWorkspaceFile else {
            statusMessage = strings.noWorkspaceFolderForFileOperation
            return
        }
        renameWorkspaceItem(selectedWorkspaceFile)
    }

    func renameWorkspaceItem(_ workspaceFile: WorkspaceFile) {
        selectWorkspaceFile(workspaceFile)
        guard let name = promptForWorkspaceName(
            title: strings.renamePromptTitle,
            message: strings.renamePromptMessage,
            defaultValue: workspaceFile.displayName
        ) else {
            return
        }
        renameWorkspaceItem(workspaceFile, to: name)
    }

    @discardableResult
    func renameWorkspaceItem(_ workspaceFile: WorkspaceFile, to rawName: String) -> URL? {
        guard let name = normalizedWorkspaceItemName(rawName) else {
            statusMessage = strings.invalidWorkspaceItemName
            return nil
        }

        let destinationURL = workspaceFile.url
            .deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: workspaceFile.isDirectory)
        if sameFileURL(destinationURL, workspaceFile.url) {
            return workspaceFile.url
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            statusMessage = strings.workspaceItemAlreadyExists
            return nil
        }

        let wasOpenFile = sameFileURL(fileURL, workspaceFile.url)

        do {
            try FileManager.default.moveItem(at: workspaceFile.url, to: destinationURL)
            expandedWorkspaceDirectories.remove(workspaceFile.id)
            if workspaceFile.isDirectory, let renamedFile = self.workspaceFile(for: destinationURL) {
                expandedWorkspaceDirectories.insert(renamedFile.id)
            }
            if wasOpenFile {
                fileURL = destinationURL
            }
            if let renamedFile = self.workspaceFile(for: destinationURL) {
                selectedWorkspaceFileID = renamedFile.id
            }
            statusMessage = strings.renamedItem(name)
            return destinationURL
        } catch {
            statusMessage = "Rename failed: \(error.localizedDescription)"
            return nil
        }
    }

    func moveSelectedWorkspaceItemToTrash() {
        guard let selectedWorkspaceFile else {
            statusMessage = strings.noWorkspaceFolderForFileOperation
            return
        }
        moveWorkspaceItemToTrash(selectedWorkspaceFile)
    }

    func moveWorkspaceItemToTrash(_ workspaceFile: WorkspaceFile) {
        selectWorkspaceFile(workspaceFile)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.deletePromptTitle
        alert.informativeText = "\(strings.deletePromptMessage)\n\n\(workspaceFile.relativePath)"
        alert.addButton(withTitle: strings.moveWorkspaceItemToTrash)
        alert.addButton(withTitle: strings.cancel)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        moveWorkspaceItemToTrash(workspaceFile, requiresConfirmation: false)
    }

    @discardableResult
    func moveWorkspaceItemToTrash(
        _ workspaceFile: WorkspaceFile,
        requiresConfirmation: Bool
    ) -> Bool {
        if requiresConfirmation {
            moveWorkspaceItemToTrash(workspaceFile)
            return true
        }

        let wasOpenFile = sameFileURL(fileURL, workspaceFile.url)

        if wasOpenFile,
           isDirty,
           !confirmDiscardUnsavedChangesIfNeeded() {
            return false
        }

        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: workspaceFile.url, resultingItemURL: &resultingURL)
            expandedWorkspaceDirectories.remove(workspaceFile.id)
            if selectedWorkspaceFileID == workspaceFile.id {
                selectedWorkspaceFileID = nil
            }
            if wasOpenFile {
                fileURL = nil
                lastSavedSnapshot = ""
            }
            statusMessage = strings.movedItemToTrash(workspaceFile.displayName)
            return true
        } catch {
            statusMessage = "Move to Trash failed: \(error.localizedDescription)"
            return false
        }
    }

    func importWithPandoc() {
        guard confirmDiscardUnsavedChangesIfNeeded() else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import with Pandoc"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "docx"),
            UTType(filenameExtension: "rtf"),
            UTType(filenameExtension: "epub"),
            .html,
            UTType(filenameExtension: "tex"),
            UTType(filenameExtension: "latex"),
        ].compactMap { $0 }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [ "pandoc", selectedURL.path, "-t", "gfm", "-o", temporaryURL.path ]
            process.currentDirectoryURL = selectedURL.deletingLastPathComponent()

            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = errorText?.isEmpty == false
                    ? "Pandoc import failed: \(errorText!)"
                    : "Pandoc import failed. Install pandoc and try again."
                try? FileManager.default.removeItem(at: temporaryURL)
                return
            }

            let contents = try String(contentsOf: temporaryURL, encoding: .utf8)
            markdown = contents
            fileURL = nil
            selectedRange = NSRange(location: 0, length: 0)
            lastSavedSnapshot = contents
            workspaceURL = selectedURL.deletingLastPathComponent()
            statusMessage = "Imported \(selectedURL.lastPathComponent) with Pandoc"
            try? FileManager.default.removeItem(at: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            statusMessage = "Pandoc import failed: \(error.localizedDescription)"
        }
    }

    func saveDocument() {
        if let fileURL {
            save(to: fileURL)
        } else {
            saveDocumentAs()
        }
    }

    func undoEditing() {
        guard let previous = undoStack.popLast() else {
            return
        }
        redoStack.append(markdown)
        applyHistorySnapshot(previous)
        statusMessage = strings.undo
    }

    func redoEditing() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(markdown)
        applyHistorySnapshot(next)
        statusMessage = strings.redo
    }

    func cutSelection() {
        NSApplication.shared.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    }

    func copySelection() {
        NSApplication.shared.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    }

    func pasteFromPasteboard() {
        NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }

    func selectAllText() {
        NSApplication.shared.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    }

    func showFindPanel() {
        sendFindAction(.showFindInterface)
    }

    func showReplacePanel() {
        sendFindAction(.showReplaceInterface)
    }

    func findNext() {
        sendFindAction(.nextMatch)
    }

    func findPrevious() {
        sendFindAction(.previousMatch)
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.title = strings.saveMarkdownFileTitle
        panel.nameFieldStringValue = displayName
        panel.allowedContentTypes = Self.markdownContentTypes

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        save(to: selectedURL)
    }

    private func save(to url: URL) {
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            lastSavedSnapshot = markdown
            statusMessage = strings.savedFile(url.lastPathComponent)
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func load(contents: String, from url: URL) {
        markdown = contents
        fileURL = url
        selectedRange = NSRange(location: 0, length: 0)
        lastSavedSnapshot = contents
        undoStack.removeAll()
        redoStack.removeAll()
        statusMessage = strings.openedFile(url.lastPathComponent)
    }

    func exportHTML() {
        exportHTML(includeStyles: true)
    }

    func exportHTMLWithoutStyles() {
        exportHTML(includeStyles: false)
    }

    private func exportHTML(includeStyles: Bool) {
        let panel = NSSavePanel()
        panel.title = includeStyles ? "Export HTML" : "Export HTML Without Styles"
        panel.nameFieldStringValue = exportBaseName(extension: "html")
        panel.allowedContentTypes = [.html]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            let html = MarkdownRenderer.renderDocument(
                markdown,
                theme: previewTheme,
                includeStyles: includeStyles
            )
            try html.write(to: selectedURL, atomically: true, encoding: .utf8)
            statusMessage = "Exported HTML to \(selectedURL.lastPathComponent)"
        } catch {
            statusMessage = "HTML export failed: \(error.localizedDescription)"
        }
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.title = "Export PDF"
        panel.nameFieldStringValue = exportBaseName(extension: "pdf")
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        statusMessage = "Exporting PDF..."
        let html = MarkdownRenderer.renderDocument(markdown, theme: previewTheme)
        let exporter = MarkdownPDFExporter(
            html: html,
            baseURL: baseURL,
            outputURL: selectedURL
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(let url):
                    self.statusMessage = "Exported PDF to \(url.lastPathComponent)"
                case .failure(let error):
                    self.statusMessage = "PDF export failed: \(error.localizedDescription)"
                }
                self.activePDFExporter = nil
            }
        }

        activePDFExporter = exporter
        exporter.start()
    }

    func exportImage() {
        let panel = NSSavePanel()
        panel.title = "Export Image"
        panel.nameFieldStringValue = exportBaseName(extension: "png")
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        statusMessage = "Exporting image..."
        let html = MarkdownRenderer.renderDocument(markdown, theme: previewTheme)
        let exporter = MarkdownImageExporter(
            html: html,
            baseURL: baseURL,
            outputURL: selectedURL
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(let url):
                    self.statusMessage = "Exported image to \(url.lastPathComponent)"
                case .failure(let error):
                    self.statusMessage = "Image export failed: \(error.localizedDescription)"
                }
                self.activeImageExporter = nil
            }
        }

        activeImageExporter = exporter
        exporter.start()
    }

    func exportWithPandoc(_ format: PandocExportFormat) {
        let panel = NSSavePanel()
        panel.title = "Export \(format.title)"
        panel.nameFieldStringValue = exportBaseName(extension: format.fileExtension)
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension)].compactMap { $0 }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        do {
            try markdown.write(to: temporaryURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["pandoc", temporaryURL.path, "-o", selectedURL.path]
            process.currentDirectoryURL = baseURL

            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            try? FileManager.default.removeItem(at: temporaryURL)

            if process.terminationStatus == 0 {
                statusMessage = "Exported \(format.title) to \(selectedURL.lastPathComponent)"
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = errorText?.isEmpty == false
                    ? "Pandoc export failed: \(errorText!)"
                    : "Pandoc export failed. Install pandoc and try again."
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            statusMessage = "Pandoc export failed: \(error.localizedDescription)"
        }
    }

    func insertHeading() {
        insertSnippet("## Heading\n\n")
    }

    func insertTableOfContents() {
        insertSnippet("[TOC]\n\n")
    }

    func insertCodeBlock() {
        insertCodeTemplate(CodeTemplate.common.first { $0.id == "swift" } ?? CodeTemplate.common[0])
    }

    func insertCodeTemplate(_ template: CodeTemplate) {
        insertSnippet(
            """
            
            ```\(template.language)
            \(template.snippet)
            ```
            
            """
        )
    }

    func insertTable() {
        insertSnippet(
            """
            
            | 项目 | 说明 | 状态 |
            | --- | --- | --- |
            | 示例 | 支持 Markdown 表格预览 | 完成 |
            
            """
        )
    }

    func insertTableRowAbove() {
        editCurrentTable { table in
            let row = table.blankDataRow()
            let insertionIndex = max(table.headerLineIndex + 2, table.focusedLineIndex)
            table.rows.insert(row, at: insertionIndex - table.startLineIndex)
            table.status = strings.addRowAbove
        }
    }

    func insertTableRowBelow() {
        editCurrentTable { table in
            let row = table.blankDataRow()
            let insertionIndex = max(table.headerLineIndex + 2, table.focusedLineIndex + 1)
            table.rows.insert(row, at: insertionIndex - table.startLineIndex)
            table.status = strings.addRowBelow
        }
    }

    func deleteCurrentTableRows() {
        editCurrentTable { table in
            let selectedIndexes = table.selectedLineIndexes.filter { $0 > table.separatorLineIndex }
            guard !selectedIndexes.isEmpty else {
                table.status = strings.chooseTableBodyRow
                return
            }

            for index in selectedIndexes.sorted(by: >) {
                table.rows.remove(at: index - table.startLineIndex)
            }

            if table.rows.count <= 2 {
                table.rows.append(table.blankDataRow())
            }
            table.status = strings.deleteRow
        }
    }

    func insertTableColumnLeft() {
        editCurrentTable { table in
            table.insertColumn(at: table.focusedColumnIndex)
            table.status = strings.addColumnLeft
        }
    }

    func insertTableColumnRight() {
        editCurrentTable { table in
            table.insertColumn(at: table.focusedColumnIndex + 1)
            table.status = strings.addColumnRight
        }
    }

    func deleteCurrentTableColumn() {
        editCurrentTable { table in
            guard table.columnCount > 1 else {
                table.status = strings.keepOneColumn
                return
            }
            table.deleteColumn(at: table.focusedColumnIndex)
            table.status = strings.deleteColumn
        }
    }

    func formatCurrentTable() {
        editCurrentTable { table in
            table.status = strings.formatTable
        }
    }

    func insertTaskList() {
        insertSnippet(
            """
            
            - [ ] First task
            - [ ] Second task
            - [x] Completed task
            
            """
        )
    }

    func insertImage() {
        let panel = NSOpenPanel()
        panel.title = strings.insertImageTitle
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .tiff, .bmp, .svg]

        guard panel.runModal() == .OK else {
            return
        }

        insertImageURLs(panel.urls)
    }

    func insertImageURLs(_ urls: [URL]) {
        let imageURLs = urls.filter(Self.isSupportedImageURL)
        guard !imageURLs.isEmpty else {
            statusMessage = strings.noSupportedImageFiles
            return
        }

        let snippets = imageURLs.map { url -> String in
            let storedURL = preparedImageURL(for: url) ?? url
            let path = markdownPath(for: storedURL)
            return "![\(storedURL.deletingPathExtension().lastPathComponent)](\(path))"
        }
        insertSnippet("\n\(snippets.joined(separator: "\n"))\n")
        statusMessage = strings.insertedImages(imageURLs.count)
    }

    func insertImageFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL],
            !urls.isEmpty
        {
            insertImageURLs(urls)
            return true
        }

        guard let image = NSImage(pasteboard: pasteboard) else {
            return false
        }

        guard let savedURL = savePastedImage(image) else {
            statusMessage = "Paste image failed. Save the document or open a folder first."
            return false
        }

        let path = markdownPath(for: savedURL)
        insertSnippet("\n![\(savedURL.deletingPathExtension().lastPathComponent)](\(path))\n")
        statusMessage = "Pasted image \(savedURL.lastPathComponent)"
        return true
    }

    func setViewMode(_ mode: EditorViewMode) {
        viewMode = mode
        statusMessage = strings.viewModeChanged(mode)
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
        statusMessage = isSidebarVisible ? strings.showSidebar : strings.hideSidebar
    }

    func setSidebarPanel(_ panel: SidebarPanel) {
        sidebarPanel = panel
        statusMessage = strings.sidebarPanelChanged(panel)
    }

    func setPreviewTheme(_ theme: PreviewTheme) {
        previewTheme = theme
        statusMessage = strings.previewThemeChanged(theme)
    }

    func toggleFocusMode() {
        focusModeEnabled.toggle()
        statusMessage = focusModeEnabled ? "Focus mode enabled" : "Focus mode disabled"
    }

    func toggleTypewriterMode() {
        typewriterModeEnabled.toggle()
        statusMessage = typewriterModeEnabled ? "Typewriter mode enabled" : "Typewriter mode disabled"
    }

    func toggleLineNumbers() {
        lineNumbersEnabled.toggle()
        statusMessage = lineNumbersEnabled ? "Line numbers enabled" : "Line numbers disabled"
    }

    func toggleAutoPair() {
        autoPairEnabled.toggle()
        statusMessage = autoPairEnabled ? "Auto pair enabled" : "Auto pair disabled"
    }

    func toggleCopyImagesToAssetFolder() {
        copyImagesToAssetFolder.toggle()
        statusMessage = copyImagesToAssetFolder
            ? "Images will be copied to assets"
            : "Images will keep original paths"
    }

    func jumpToOutlineItem(_ item: OutlineItem) {
        selectedRange = NSRange(location: item.location, length: 0)
        if viewMode == .preview {
            viewMode = .split
        }
        navigationRevision += 1
        editorNavigationTarget = SourceLineScrollTarget(
            line: item.line,
            revision: navigationRevision,
            location: item.location,
            anchorID: MarkdownRenderer.headingAnchorID(for: item.title)
        )
        statusMessage = strings.jumpTo(item.title)
    }

    func showHelp() {
        let alert = NSAlert()
        alert.messageText = strings.helpTitle
        alert.informativeText = strings.helpMessage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func openMarkdownSyntaxReference() {
        guard let url = URL(string: "https://www.markdownguide.org/basic-syntax/") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func checkForUpdates() {
        statusMessage = strings.checkingForUpdates

        Task { [weak self] in
            await self?.performUpdateCheck()
        }
    }

    private func performUpdateCheck() async {
        let currentVersion = Self.currentAppVersion

        do {
            let release = try await Self.fetchLatestGitHubRelease()
            let latestVersion = release.tagName
            let asset = release.preferredMacAsset
            let downloadURL = asset?.browserDownloadURL ?? release.htmlURL

            if ReleaseVersionComparator.isNewer(latestVersion, than: currentVersion) {
                showUpdateAvailableAlert(
                    currentVersion: currentVersion,
                    latestVersion: latestVersion,
                    assetName: asset?.name,
                    downloadURL: downloadURL
                )
                statusMessage = strings.updateAvailableTitle
            } else {
                showNoUpdateAlert(currentVersion: currentVersion, releasesURL: release.htmlURL)
                statusMessage = strings.noUpdateTitle
            }
        } catch {
            showUpdateCheckFailedAlert()
            statusMessage = strings.updateCheckFailedTitle
        }
    }

    private static func fetchLatestGitHubRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/moye-source/moye-md/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Moye/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func showUpdateAvailableAlert(
        currentVersion: String,
        latestVersion: String,
        assetName: String?,
        downloadURL: URL
    ) {
        let alert = NSAlert()
        alert.messageText = strings.updateAvailableTitle
        alert.informativeText = strings.updateAvailableMessage(
            current: currentVersion,
            latest: latestVersion,
            assetName: assetName
        )
        alert.addButton(withTitle: strings.openDownloadPage)
        alert.addButton(withTitle: strings.cancel)

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private func showNoUpdateAlert(currentVersion: String, releasesURL: URL) {
        let alert = NSAlert()
        alert.messageText = strings.noUpdateTitle
        alert.informativeText = strings.noUpdateMessage(current: currentVersion)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: strings.openDownloadPage)

        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(releasesURL)
        }
    }

    private func showUpdateCheckFailedAlert() {
        let alert = NSAlert()
        alert.messageText = strings.updateCheckFailedTitle
        alert.informativeText = strings.updateCheckFailedMessage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: strings.openDownloadPage)

        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/moye-source/moye-md/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    private func insertSnippet(_ snippet: String) {
        let nsMarkdown = markdown as NSString
        let safeRange = selectedRange.clamped(toLength: nsMarkdown.length) ?? NSRange(
            location: nsMarkdown.length,
            length: 0
        )
        markdown = nsMarkdown.replacingCharacters(in: safeRange, with: snippet)

        let insertedLength = (snippet as NSString).length
        selectedRange = NSRange(location: safeRange.location + insertedLength, length: 0)
        statusMessage = strings.insertedMarkdownBlock
    }

    private func sendFindAction(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApplication.shared.sendAction(
            #selector(NSTextView.performFindPanelAction(_:)),
            to: nil,
            from: sender
        )
    }

    private func applyHistorySnapshot(_ snapshot: String) {
        isApplyingHistory = true
        markdown = snapshot
        isApplyingHistory = false
        selectedRange = selectedRange.clamped(toLength: (markdown as NSString).length)
            ?? NSRange(location: (markdown as NSString).length, length: 0)
    }

    private func registerUndoSnapshot(_ previous: String, replacingWith next: String) {
        guard !isApplyingHistory, previous != next else {
            return
        }
        if undoStack.last != previous {
            undoStack.append(previous)
        }
        if undoStack.count > 200 {
            undoStack.removeFirst(undoStack.count - 200)
        }
        redoStack.removeAll()
    }

    func confirmDiscardUnsavedChangesIfNeeded() -> Bool {
        guard isDirty else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.unsavedPromptTitle
        alert.informativeText = strings.unsavedPromptMessage
        alert.addButton(withTitle: strings.save)
        alert.addButton(withTitle: strings.discardChanges)
        alert.addButton(withTitle: strings.cancel)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func localizeMainMenu() {
        MainMenuLocalizer.localize(language: language)
    }

    private func promptForWorkspaceName(
        title: String,
        message: String,
        defaultValue: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: strings.done)
        alert.addButton(withTitle: strings.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return textField.stringValue
    }

    private func normalizedWorkspaceItemName(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return nil
        }
        return name
    }

    private func sameFileURL(_ lhs: URL?, _ rhs: URL) -> Bool {
        lhs?.resolvingSymlinksInPath().path == rhs.resolvingSymlinksInPath().path
    }

    private func targetDirectoryURL(for targetItem: WorkspaceFile?) -> URL? {
        guard let workspaceURL else {
            statusMessage = strings.noWorkspaceFolderForFileOperation
            return nil
        }

        guard let targetItem else {
            return workspaceURL
        }

        return targetItem.isDirectory
            ? targetItem.url
            : targetItem.url.deletingLastPathComponent()
    }

    private func expandWorkspaceDirectory(for directoryURL: URL) {
        guard
            directoryURL.standardizedFileURL != workspaceURL?.standardizedFileURL,
            let directoryFile = workspaceFile(for: directoryURL)
        else {
            return
        }
        expandedWorkspaceDirectories.insert(directoryFile.id)
    }

    private func workspaceFile(for url: URL) -> WorkspaceFile? {
        guard
            let workspaceURL,
            let relativePath = url.relativePath(from: workspaceURL),
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        else {
            return nil
        }

        let isDirectory = resourceValues.isDirectory == true
        let isRegularFile = resourceValues.isRegularFile == true
        guard isDirectory || isRegularFile else {
            return nil
        }

        return WorkspaceFile(
            id: url.path,
            url: url,
            relativePath: relativePath,
            isDirectory: isDirectory,
            isTextLike: !isDirectory && Self.isTextLikeURL(url)
        )
    }

    private func workspaceSearchResults(
        matching rawQuery: String,
        includeDirectories: Bool,
        includeUnsupportedFiles: Bool
    ) -> [WorkspaceSearchResult] {
        let files = workspaceFiles.filter { file in
            if file.isDirectory {
                return includeDirectories
            }
            if file.isTextLike {
                return true
            }
            return includeUnsupportedFiles
        }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return files.map { WorkspaceSearchResult(file: $0, matchKind: .path, snippet: nil) }
        }

        return files.compactMap { file in
            if file.displayName.localizedCaseInsensitiveContains(query) {
                return WorkspaceSearchResult(file: file, matchKind: .fileName, snippet: file.relativePath)
            }

            if file.relativePath.localizedCaseInsensitiveContains(query) {
                return WorkspaceSearchResult(file: file, matchKind: .path, snippet: file.relativePath)
            }

            guard
                file.isTextLike,
                let contents = try? String(contentsOf: file.url, encoding: .utf8),
                let matchingLine = contents
                    .components(separatedBy: .newlines)
                    .first(where: { $0.localizedCaseInsensitiveContains(query) })
            else {
                return nil
            }

            return WorkspaceSearchResult(
                file: file,
                matchKind: .content,
                snippet: matchingLine.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func markdownPath(for url: URL) -> String {
        let rawPath: String
        if let baseURL, let relativePath = url.relativePath(from: baseURL) {
            rawPath = relativePath
        } else {
            rawPath = url.path
        }

        return rawPath.addingPercentEncoding(withAllowedCharacters: .markdownPathAllowed) ?? rawPath
    }

    private func preparedImageURL(for url: URL) -> URL? {
        guard copyImagesToAssetFolder, let assetFolderURL else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: assetFolderURL,
                withIntermediateDirectories: true
            )
            let destinationURL = uniqueURL(
                in: assetFolderURL,
                preferredName: url.lastPathComponent
            )
            if url.standardizedFileURL != destinationURL.standardizedFileURL {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            }
            return destinationURL
        } catch {
            statusMessage = "Copy image failed: \(error.localizedDescription)"
            return nil
        }
    }

    private func savePastedImage(_ image: NSImage) -> URL? {
        guard let assetFolderURL else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: assetFolderURL,
                withIntermediateDirectories: true
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let fileName = "pasted-\(formatter.string(from: Date())).png"
            let destinationURL = uniqueURL(in: assetFolderURL, preferredName: fileName)

            guard
                let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData),
                let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                return nil
            }

            try pngData.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            statusMessage = "Paste image failed: \(error.localizedDescription)"
            return nil
        }
    }

    private var assetFolderURL: URL? {
        if let baseURL {
            return baseURL.appendingPathComponent("assets", isDirectory: true)
        }
        if let workspaceURL {
            return workspaceURL.appendingPathComponent("assets", isDirectory: true)
        }
        return nil
    }

    private func uniqueURL(in folderURL: URL, preferredName: String) -> URL {
        let baseURL = folderURL.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let name = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension
        var counter = 2
        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(name)-\(counter)"
                : "\(name)-\(counter).\(fileExtension)"
            let candidateURL = folderURL.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    private func exportBaseName(extension fileExtension: String) -> String {
        let baseName = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return "\(baseName).\(fileExtension)"
    }

    private func editCurrentTable(_ mutation: (inout MarkdownTableEdit) -> Void) {
        let nsMarkdown = markdown as NSString
        let lines = MarkdownLine.lines(in: markdown)
        guard
            !lines.isEmpty,
            let table = MarkdownTableEdit(
                lines: lines,
                markdown: nsMarkdown,
                selectedRange: selectedRange
            )
        else {
            statusMessage = strings.cursorNotInTable
            return
        }

        var mutableTable = table
        mutation(&mutableTable)

        let replacement = mutableTable.renderedRows().joined(separator: "\n")
        let replaceRange = NSRange(
            location: table.blockRange.location,
            length: table.blockRange.length
        )
        markdown = nsMarkdown.replacingCharacters(in: replaceRange, with: replacement)
        selectedRange = NSRange(location: table.blockRange.location, length: 0)
        statusMessage = mutableTable.status ?? strings.formatTable
    }

    private static var markdownContentTypes: [UTType] {
        [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText,
        ].compactMap { $0 }
    }

    private static func parentPath(for relativePath: String) -> String {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 1 else {
            return ""
        }
        return components.dropLast().joined(separator: "/")
    }

    private static func sortWorkspaceFiles(_ lhs: WorkspaceFile, _ rhs: WorkspaceFile) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }

    private static func isTextLikeURL(_ url: URL) -> Bool {
        [
            "md", "markdown", "txt",
            "swift", "js", "jsx", "ts", "tsx", "vue", "svelte",
            "html", "htm", "css", "scss", "sass", "less",
            "json", "yml", "yaml", "toml", "xml", "plist",
            "sh", "bash", "zsh", "py", "rb", "go", "rs", "java", "kt",
            "sql", "conf", "config", "ini", "env", "dockerfile",
        ].contains(url.pathExtension.lowercased()) || ["dockerfile", "makefile", "justfile"].contains(url.lastPathComponent.lowercased())
    }

    private static func isSupportedImageURL(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "svg"]
            .contains(url.pathExtension.lowercased())
    }

    private static func defaultDocument(for language: AppLanguage) -> String {
        let logoDataURL = "data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20viewBox='0%200%20640%20360'%3E%3Crect%20width='640'%20height='360'%20rx='36'%20fill='%231a1f2b'/%3E%3Cpath%20d='M164%20258V102h54l58%2074%2058-74h54v156h-48V172l-53%2067h-23l-53-67v86z'%20fill='%23f7f3e8'/%3E%3Cpath%20d='M444%20102h72l-84%20156h-57z'%20fill='%2359c2ff'/%3E%3Ccircle%20cx='496'%20cy='94'%20r='26'%20fill='%23ffcf5a'/%3E%3C/svg%3E"

        switch language {
        case .chinese:
            return """
            ---
            title: 墨页 Markdown 语法示例
            author: Moye
            tags: [markdown, editor, preview]
            ---

            # 墨页

            这份默认文档用于检查常见 Markdown 语法、开发代码块、运维配置和图片预览。

            [TOC]

            ## 1. 标题

            # 一级标题
            ## 二级标题
            ### 三级标题
            #### 四级标题
            ##### 五级标题
            ###### 六级标题

            ## 2. 段落与行内样式

            普通段落支持 **加粗**、*斜体*、~~删除线~~、==高亮==、上标 x^2^、下标 H~2~O、`inline code`、自动链接 https://example.com 和表情短码 :smile:。

            [行内链接](https://example.com) 和 [引用式链接][moye-link] 都可以预览。

            ## 3. 引用

            > 第一层引用，适合放提示、摘录或摘要。

            ## 4. 列表

            - 无序列表 A
            - 无序列表 B
              - 子项目 B.1
              - 子项目 B.2

            1. 有序列表 A
            2. 有序列表 B
            3. 有序列表 C

            - [ ] 待办任务
            - [x] 已完成任务

            ## 5. 表格

            | 语法 | 用途 | 状态 |
            | --- | --- | --- |
            | `#` | 标题 | 支持 |
            | `|` | 表格 | 支持 |
            | `- [ ]` | 任务列表 | 支持 |

            ## 6. 图片

            ![墨页示例图片](\(logoDataURL))

            也支持本地绝对路径或相对路径，路径里有空格时也会转成可预览的文件 URL。

            ## 7. 代码块

            ```swift
            print("你好，Markdown")
            ```

            ```typescript
            type Document = {
              title: string
              body: string
            }
            ```

            ```python
            from pathlib import Path
            print(Path.cwd())
            ```

            ```bash
            set -euo pipefail
            echo "deploy"
            ```

            ```json
            {
              "name": "moye",
              "private": true
            }
            ```

            ```yaml
            service:
              name: moye
              port: 8080
            ```

            ```toml
            [server]
            host = "127.0.0.1"
            port = 8080
            ```

            ```nginx
            server {
              listen 80;
              server_name example.com;

              location / {
                proxy_pass http://127.0.0.1:8080;
              }
            }
            ```

            ## 8. 数学与图表

            行内公式 $E = mc^2$。

            $$
            a^2 + b^2 = c^2
            $$

            ```mermaid
            flowchart LR
              A[编辑 Markdown] --> B[实时预览]
              B --> C[导出 HTML/PDF/图片]
            ```

            ## 9. 分隔线、脚注和引用链接

            ---

            这是一段带脚注的文字。[^note]

            [moye-link]: https://example.com "墨页"
            [^note]: 脚注内容会统一显示在文档底部。
            """
        case .english:
            return """
            ---
            title: Moye Markdown Syntax Sample
            author: Moye
            tags: [markdown, editor, preview]
            ---

            # Moye

            This starter file exercises common Markdown syntax, developer code blocks, ops configuration, and image rendering.

            [TOC]

            ## Headings

            # H1
            ## H2
            ### H3
            #### H4
            ##### H5
            ###### H6

            ## Inline Syntax

            Paragraphs support **bold**, *italic*, ~~strike~~, ==mark==, x^2^, H~2~O, `inline code`, autolinks like https://example.com, and emoji shortcodes :smile:.

            [Inline links](https://example.com) and [reference links][moye-link] are supported.

            ## Lists

            - Bullet A
            - Bullet B
              - Nested B.1
              - Nested B.2

            1. Ordered A
            2. Ordered B
            3. Ordered C

            - [ ] Todo item
            - [x] Done item

            ## Table

            | Syntax | Purpose | Status |
            | --- | --- | --- |
            | `#` | Heading | Supported |
            | `|` | Table | Supported |
            | `- [ ]` | Task list | Supported |

            ## Image

            ![Moye sample image](\(logoDataURL))

            Local absolute and relative image paths are also supported, including paths with spaces.

            ## Code Blocks

            ```swift
            print("Hello Markdown")
            ```

            ```typescript
            type Document = {
              title: string
              body: string
            }
            ```

            ```python
            from pathlib import Path
            print(Path.cwd())
            ```

            ```bash
            set -euo pipefail
            echo "deploy"
            ```

            ```json
            {
              "name": "moye",
              "private": true
            }
            ```

            ```yaml
            service:
              name: moye
              port: 8080
            ```

            ```toml
            [server]
            host = "127.0.0.1"
            port = 8080
            ```

            ```nginx
            server {
              listen 80;
              server_name example.com;

              location / {
                proxy_pass http://127.0.0.1:8080;
              }
            }
            ```

            ## Math and Diagrams

            Inline math: $E = mc^2$.

            $$
            a^2 + b^2 = c^2
            $$

            ```mermaid
            flowchart LR
              A[Edit Markdown] --> B[Live Preview]
              B --> C[Export HTML/PDF/Image]
            ```

            ## Rule, Footnote, Reference Link

            ---

            This sentence has a footnote.[^note]

            [moye-link]: https://example.com "Moye"
            [^note]: Footnotes render at the bottom of the document.
            """
        }
    }
}

private struct MarkdownLine {
    let text: String
    let range: NSRange

    static func lines(in markdown: String) -> [MarkdownLine] {
        let nsMarkdown = markdown as NSString
        var result: [MarkdownLine] = []
        var location = 0

        while location <= nsMarkdown.length {
            let lineRange = nsMarkdown.lineRange(for: NSRange(location: location, length: 0))
            let lineText = nsMarkdown.substring(with: lineRange)
                .trimmingCharacters(in: .newlines)
            result.append(MarkdownLine(text: lineText, range: lineRange))
            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location, nextLocation < nsMarkdown.length else {
                break
            }
            location = nextLocation
        }

        if result.isEmpty {
            result.append(MarkdownLine(text: "", range: NSRange(location: 0, length: 0)))
        }

        return result
    }
}

private struct MarkdownTableEdit {
    let startLineIndex: Int
    let headerLineIndex: Int
    let separatorLineIndex: Int
    let endLineIndex: Int
    let blockRange: NSRange
    let focusedLineIndex: Int
    let focusedColumnIndex: Int
    let selectedLineIndexes: [Int]
    var rows: [[String]]
    var status: String?

    var columnCount: Int {
        rows.first?.count ?? 1
    }

    init?(lines: [MarkdownLine], markdown: NSString, selectedRange: NSRange) {
        let focusedLocation = min(selectedRange.location, markdown.length)
        guard let currentLineIndex = lines.firstIndex(where: { line in
            NSLocationInRange(focusedLocation, line.range) ||
                focusedLocation == NSMaxRange(line.range)
        }) else {
            return nil
        }

        var start = currentLineIndex
        while start > 0, Self.isTableLikeLine(lines[start - 1].text) {
            start -= 1
        }

        var end = currentLineIndex
        while end + 1 < lines.count, Self.isTableLikeLine(lines[end + 1].text) {
            end += 1
        }

        guard end - start >= 1 else {
            return nil
        }

        var header = start
        while header + 1 <= end, !Self.isSeparatorLine(lines[header + 1].text) {
            header += 1
        }

        guard header + 1 <= end, Self.isSeparatorLine(lines[header + 1].text) else {
            return nil
        }

        let rawRows = (header...end).map { Self.splitRow(lines[$0].text) }
        let count = max(1, rawRows.map(\.count).max() ?? 1)
        self.rows = rawRows.map { Self.normalized($0, count: count) }
        self.startLineIndex = header
        self.headerLineIndex = header
        self.separatorLineIndex = header + 1
        self.endLineIndex = end
        self.focusedLineIndex = min(max(currentLineIndex, header), end)
        self.focusedColumnIndex = Self.columnIndex(
            in: lines[currentLineIndex],
            selectedLocation: focusedLocation,
            columnCount: count
        )

        let selectedEnd = max(selectedRange.location, selectedRange.location + selectedRange.length)
        let selectedIndexes = (header...end).filter { lineIndex in
            let range = lines[lineIndex].range
            return selectedRange.length == 0
                ? lineIndex == currentLineIndex
                : range.location < selectedEnd && NSMaxRange(range) > selectedRange.location
        }
        self.selectedLineIndexes = selectedIndexes.isEmpty ? [currentLineIndex] : selectedIndexes

        let firstRange = lines[header].range
        let lastRange = lines[end].range
        self.blockRange = NSRange(
            location: firstRange.location,
            length: NSMaxRange(lastRange) - firstRange.location
        )
    }

    mutating func insertColumn(at index: Int) {
        let target = min(max(0, index), columnCount)
        rows = rows.enumerated().map { rowIndex, row in
            var mutableRow = row
            mutableRow.insert(rowIndex == 1 ? "---" : "", at: target)
            return mutableRow
        }
    }

    mutating func deleteColumn(at index: Int) {
        let target = min(max(0, index), columnCount - 1)
        rows = rows.map { row in
            var mutableRow = row
            mutableRow.remove(at: target)
            return mutableRow
        }
    }

    func blankDataRow() -> [String] {
        Array(repeating: "", count: columnCount)
    }

    func renderedRows() -> [String] {
        rows.enumerated().map { rowIndex, row in
            let cells = Self.normalized(row, count: columnCount)
            if rowIndex == 1 {
                return "| \(Array(repeating: "---", count: columnCount).joined(separator: " | ")) |"
            }
            return "| \(cells.joined(separator: " | ")) |"
        }
    }

    private static func isTableLikeLine(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        let cells = splitRow(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") {
            row.removeFirst()
        }
        if row.hasSuffix("|") {
            row.removeLast()
        }
        return row
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func normalized(_ row: [String], count: Int) -> [String] {
        row.count >= count ? Array(row.prefix(count)) : row + Array(repeating: "", count: count - row.count)
    }

    private static func columnIndex(
        in line: MarkdownLine,
        selectedLocation: Int,
        columnCount: Int
    ) -> Int {
        let offset = max(0, selectedLocation - line.range.location)
        let prefix = (line.text as NSString).substring(
            with: NSRange(location: 0, length: min(offset, (line.text as NSString).length))
        )
        let pipeCount = prefix.filter { $0 == "|" }.count
        if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            return min(max(0, pipeCount - 1), columnCount - 1)
        }
        return min(max(0, pipeCount), columnCount - 1)
    }
}

private extension URL {
    func relativePath(from baseURL: URL) -> String? {
        let standardizedBase = baseURL.standardizedFileURL
        let standardizedTarget = standardizedFileURL
        let baseComponents = standardizedBase.pathComponents
        let targetComponents = standardizedTarget.pathComponents

        var sharedPrefixCount = 0
        while
            sharedPrefixCount < baseComponents.count,
            sharedPrefixCount < targetComponents.count,
            baseComponents[sharedPrefixCount] == targetComponents[sharedPrefixCount]
        {
            sharedPrefixCount += 1
        }

        guard sharedPrefixCount > 0 else {
            return nil
        }

        let upLevels = Array(repeating: "..", count: baseComponents.count - sharedPrefixCount)
        let remaining = targetComponents.dropFirst(sharedPrefixCount)
        let relativeComponents = upLevels + remaining

        guard !relativeComponents.isEmpty else {
            return lastPathComponent
        }

        return relativeComponents.joined(separator: "/")
    }
}

struct ReleaseVersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(in: candidate)
        let currentParts = numericParts(in: current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let left = index < candidateParts.count ? candidateParts[index] : 0
            let right = index < currentParts.count ? currentParts[index] : 0
            if left != right {
                return left > right
            }
        }

        return false
    }

    private static func numericParts(in version: String) -> [Int] {
        let normalized = version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? version

        let stableCore = normalized
            .split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? normalized

        return stableCore
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    var preferredMacAsset: GitHubReleaseAsset? {
        let zipAssets = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        return zipAssets.first { asset in
            let name = asset.name.lowercased()
            return name.contains("macos") || name.contains("moye")
        } ?? zipAssets.first
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private extension CharacterSet {
    static var markdownPathAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "#?&=%")
        return allowed
    }
}
