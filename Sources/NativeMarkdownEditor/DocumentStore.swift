import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var markdown: String {
        willSet {
            if let pendingTextBufferEdit {
                registerUndoEdit(pendingTextBufferEdit)
            } else {
                registerUndoSnapshot(markdown, replacingWith: newValue)
            }
        }
        didSet {
            if !isPublishingTextBufferSnapshot {
                textBuffer.reset(markdown)
            }
            markMarkdownEdited()
            if isPublishingTextBufferSnapshot, let pendingTextBufferEdit {
                refreshDerivedData(snapshot: markdown, edit: pendingTextBufferEdit.markdownTextEdit)
            } else {
                scheduleDerivedDataRefresh(for: markdown, replacing: oldValue)
            }
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
    @Published var performanceDiagnosticsEnabled: Bool
    @Published var language: AppLanguage
    @Published var workspaceURL: URL? {
        didSet {
            guard workspaceURL?.standardizedFileURL.path != oldValue?.standardizedFileURL.path else {
                return
            }
            reloadWorkspaceFiles()
        }
    }
    @Published var fileSearchQuery: String {
        didSet {
            guard fileSearchQuery != oldValue else {
                return
            }
            rebuildWorkspaceSearchCaches()
        }
    }
    @Published var expandedWorkspaceDirectories: Set<String> {
        didSet {
            rebuildVisibleWorkspaceTreeRowsCache()
        }
    }
    @Published var selectedWorkspaceFileID: String?
    @Published var isQuickOpenPresented: Bool
    @Published var quickOpenQuery: String {
        didSet {
            guard quickOpenQuery != oldValue else {
                return
            }
            rebuildWorkspaceSearchCaches()
        }
    }
    @Published private(set) var fileURL: URL?
    @Published private(set) var statusMessage: String
    @Published private(set) var blockIndex: MarkdownBlockIndex
    @Published private(set) var outline: [OutlineItem]
    @Published private(set) var activeOutlineItemID: OutlineItem.ID?
    @Published private(set) var statistics: DocumentStatistics
    @Published private(set) var editorNavigationTarget: SourceLineScrollTarget?
    @Published private(set) var documentRevision: Int
    @Published private(set) var isDirty: Bool
    @Published private(set) var workspaceSearchResults: [WorkspaceSearchResult]
    @Published private(set) var quickOpenResults: [WorkspaceSearchResult]
    @Published private(set) var workspaceFiles: [WorkspaceFile] {
        didSet {
            rebuildWorkspaceTreeCache()
            rebuildWorkspaceSearchCaches()
        }
    }

    private static let immediateDerivedDataCharacterLimit = 120_000
    private static let exactDirtyCompareCharacterLimit = 120_000
    private static let undoCoalescingInterval: TimeInterval = 3.0

    private var lastSavedSnapshot: String
    private var savedDocumentRevision: Int
    private var activePDFExporter: MarkdownPDFExporter?
    private var activeImageExporter: MarkdownImageExporter?
    private var undoStack: [DocumentEditDelta]
    private var redoStack: [DocumentEditDelta]
    private var isApplyingHistory: Bool
    private var textBuffer: PieceTableTextBuffer
    private var isPublishingTextBufferSnapshot: Bool
    private var pendingTextBufferEdit: TextBufferEdit?
    private var lastUndoRegistrationDate: Date?
    private var navigationRevision: Int
    private var activeOutlineSourceLine: Int
    private var blockIndexRevision: Int
    private var derivedDataRefreshRequestID: Int
    private var derivedDataRefreshWork: DispatchWorkItem?
    private var pendingDerivedDataBaseMarkdown: String?
    private var forceImmediateDerivedDataRefresh: Bool
    private var undoMemoryCost: Int
    private var redoMemoryCost: Int
    private var workspaceTextCache: [String: WorkspaceTextCacheEntry]
    private var workspaceFileByIDCache: [String: WorkspaceFile]
    private var workspaceTreeCache: [WorkspaceTreeNode]
    private var visibleWorkspaceTreeRowsCache: [WorkspaceTreeRow]

    private static let undoMemoryBudget = 4_000_000
    private static let workspaceContentSearchFileSizeLimit = 2_000_000

    init(initialDocumentURL: URL? = nil) {
        let initialLanguage = AppLanguage.chinese
        let sample = Self.defaultDocument(for: initialLanguage)
        let initialBlockIndex = MarkdownBlockIndex(markdown: sample)
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
        performanceDiagnosticsEnabled = true
        language = initialLanguage
        workspaceURL = nil
        workspaceFiles = []
        fileSearchQuery = ""
        expandedWorkspaceDirectories = []
        selectedWorkspaceFileID = nil
        isQuickOpenPresented = false
        quickOpenQuery = ""
        blockIndex = initialBlockIndex
        outline = initialBlockIndex.outline
        statistics = initialBlockIndex.statistics
        editorNavigationTarget = nil
        documentRevision = 0
        isDirty = false
        workspaceSearchResults = []
        quickOpenResults = []
        lastSavedSnapshot = sample
        savedDocumentRevision = 0
        statusMessage = LocalizedStrings(language: initialLanguage).ready
        activeOutlineItemID = nil
        undoStack = []
        redoStack = []
        isApplyingHistory = false
        textBuffer = PieceTableTextBuffer(sample)
        isPublishingTextBufferSnapshot = false
        pendingTextBufferEdit = nil
        lastUndoRegistrationDate = nil
        navigationRevision = 0
        activeOutlineSourceLine = 1
        blockIndexRevision = initialBlockIndex.revision
        derivedDataRefreshRequestID = 0
        pendingDerivedDataBaseMarkdown = nil
        forceImmediateDerivedDataRefresh = false
        undoMemoryCost = 0
        redoMemoryCost = 0
        workspaceTextCache = [:]
        workspaceFileByIDCache = [:]
        workspaceTreeCache = []
        visibleWorkspaceTreeRowsCache = []
        PerformanceDiagnostics.shared.setEnabled(true)

        if let initialDocumentURL {
            _ = openDocument(at: initialDocumentURL, requiresConfirmation: false)
        }
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

    var wordCount: Int {
        statistics.wordCount
    }

    var characterCount: Int {
        statistics.characterCount
    }

    var lineCount: Int {
        statistics.lineCount
    }

    var readingMinutes: Int {
        statistics.readingMinutes
    }

    private func scheduleDerivedDataRefresh(for markdown: String, replacing oldMarkdown: String? = nil) {
        derivedDataRefreshWork?.cancel()
        derivedDataRefreshWork = nil
        derivedDataRefreshRequestID += 1
        let requestID = derivedDataRefreshRequestID

        let shouldRefreshImmediately = forceImmediateDerivedDataRefresh ||
            markdown.utf16.count <= Self.immediateDerivedDataCharacterLimit

        if shouldRefreshImmediately {
            pendingDerivedDataBaseMarkdown = nil
            let snapshot = markdown
            let edit = oldMarkdown.flatMap { MarkdownTextEdit.diff(old: $0, new: markdown) }
            refreshDerivedData(snapshot: snapshot, edit: edit)
            return
        }

        if pendingDerivedDataBaseMarkdown == nil {
            pendingDerivedDataBaseMarkdown = oldMarkdown
        }
        let baseMarkdown = pendingDerivedDataBaseMarkdown
        let refresh = DispatchWorkItem { [weak self] in
            guard let self, self.derivedDataRefreshRequestID == requestID else {
                return
            }

            let snapshot = self.markdown
            let edit = baseMarkdown.flatMap { MarkdownTextEdit.diff(old: $0, new: snapshot) }
            self.refreshDerivedData(snapshot: snapshot, edit: edit)
            self.pendingDerivedDataBaseMarkdown = nil
            self.derivedDataRefreshWork = nil
        }

        derivedDataRefreshWork = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: refresh)
    }

    private func refreshDerivedData(snapshot: String, edit: MarkdownTextEdit?) {
        blockIndexRevision += 1
        let nextBlockIndex = PerformanceDiagnostics.shared.measure(
            "derived-data.refresh",
            metadata: [
                "characters": "\(snapshot.utf16.count)",
                "edit": edit == nil ? "full" : "incremental",
            ]
        ) {
            blockIndex.updating(
                markdown: snapshot,
                edit: edit,
                revision: blockIndexRevision
            )
        }
        blockIndex = nextBlockIndex
        statistics = nextBlockIndex.statistics
        outline = nextBlockIndex.outline
        updateActiveOutline(forSourceLine: activeOutlineSourceLine)
    }

    private func setMarkdown(_ newMarkdown: String, refreshDerivedDataImmediately: Bool) {
        forceImmediateDerivedDataRefresh = refreshDerivedDataImmediately
        markdown = newMarkdown
        forceImmediateDerivedDataRefresh = false
    }

    private func markMarkdownEdited() {
        documentRevision += 1
        let canCompareExactly = markdown.utf16.count <= Self.exactDirtyCompareCharacterLimit &&
            lastSavedSnapshot.utf16.count <= Self.exactDirtyCompareCharacterLimit
        if canCompareExactly {
            isDirty = markdown != lastSavedSnapshot
        } else {
            isDirty = documentRevision != savedDocumentRevision
        }
    }

    private func markDocumentClean(snapshot: String) {
        lastSavedSnapshot = snapshot
        savedDocumentRevision = documentRevision
        isDirty = false
    }

    var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var workspaceTitle: String {
        workspaceURL?.lastPathComponent ?? strings.noFolder
    }

    private func reloadWorkspaceFiles() {
        guard let workspaceURL else {
            workspaceTextCache = [:]
            workspaceFiles = []
            return
        }
        let scannedFiles = Self.scanWorkspaceFiles(in: workspaceURL)
        let validFileIDs = Set(scannedFiles.map(\.id))
        expandedWorkspaceDirectories = expandedWorkspaceDirectories.intersection(validFileIDs)
        workspaceTextCache = workspaceTextCache.filter { validFileIDs.contains($0.key) }
        workspaceFiles = scannedFiles
    }

    var workspaceTree: [WorkspaceTreeNode] {
        workspaceTreeCache
    }

    var visibleWorkspaceTreeRows: [WorkspaceTreeRow] {
        visibleWorkspaceTreeRowsCache
    }

    private func rebuildWorkspaceTreeCache() {
        workspaceFileByIDCache = Dictionary(
            uniqueKeysWithValues: workspaceFiles.map { ($0.id, $0) }
        )

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

        workspaceTreeCache = makeNodes(parentPath: "")
        rebuildVisibleWorkspaceTreeRowsCache()
    }

    private func rebuildVisibleWorkspaceTreeRowsCache() {
        var rows: [WorkspaceTreeRow] = []

        func append(nodes: [WorkspaceTreeNode], depth: Int) {
            for node in nodes {
                rows.append(WorkspaceTreeRow(file: node.file, depth: depth))
                if node.file.isDirectory, isWorkspaceDirectoryExpanded(node.file) {
                    append(nodes: node.children, depth: depth + 1)
                }
            }
        }

        append(nodes: workspaceTreeCache, depth: 0)
        visibleWorkspaceTreeRowsCache = rows
    }

    private func rebuildWorkspaceSearchCaches() {
        workspaceSearchResults = makeWorkspaceSearchResults(
            matching: fileSearchQuery,
            includeDirectories: true,
            includeUnsupportedFiles: true
        )
        quickOpenResults = makeWorkspaceSearchResults(
            matching: quickOpenQuery,
            includeDirectories: false,
            includeUnsupportedFiles: false
        )
    }

    var selectedWorkspaceFile: WorkspaceFile? {
        guard let selectedWorkspaceFileID else {
            return nil
        }
        return workspaceFileByIDCache[selectedWorkspaceFileID]
    }

    func newDocument() {
        guard confirmDiscardUnsavedChangesIfNeeded() else {
            return
        }
        markdown = Self.defaultDocument(for: language)
        fileURL = nil
        selectedRange = NSRange(location: (markdown as NSString).length, length: 0)
        markDocumentClean(snapshot: markdown)
        clearEditingHistory()
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

        openDocument(at: selectedURL, requiresConfirmation: false)
    }

    @discardableResult
    func openDocument(at url: URL, requiresConfirmation: Bool = true) -> Bool {
        if requiresConfirmation, !confirmDiscardUnsavedChangesIfNeeded() {
            return false
        }

        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                workspaceURL = url
                fileSearchQuery = ""
                expandedWorkspaceDirectories.removeAll()
                selectedWorkspaceFileID = nil
                quickOpenQuery = ""
                statusMessage = strings.openedFolder(url.lastPathComponent)
                return true
            }

            let contents = try String(contentsOf: url, encoding: .utf8)
            load(contents: contents, from: url)
            workspaceURL = url.deletingLastPathComponent()
            return true
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
            return false
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
            reloadWorkspaceFiles()
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
            reloadWorkspaceFiles()
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
            reloadWorkspaceFiles()
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
            reloadWorkspaceFiles()
            if selectedWorkspaceFileID == workspaceFile.id {
                selectedWorkspaceFileID = nil
            }
            if wasOpenFile {
                fileURL = nil
                lastSavedSnapshot = ""
                savedDocumentRevision = documentRevision
                isDirty = !markdown.isEmpty
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
            markDocumentClean(snapshot: contents)
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
        guard let edit = undoStack.last else {
            return
        }
        guard applyHistoryEdit(edit, direction: .undo) else {
            statusMessage = strings.undo
            return
        }
        undoStack.removeLast()
        undoMemoryCost -= edit.memoryCost
        redoStack.append(edit)
        redoMemoryCost += edit.memoryCost
        lastUndoRegistrationDate = nil
        trimRedoStackIfNeeded()
        statusMessage = strings.undo
    }

    func redoEditing() {
        guard let edit = redoStack.last else {
            return
        }
        guard applyHistoryEdit(edit, direction: .redo) else {
            statusMessage = strings.redo
            return
        }
        redoStack.removeLast()
        redoMemoryCost -= edit.memoryCost
        undoStack.append(edit)
        undoMemoryCost += edit.memoryCost
        lastUndoRegistrationDate = nil
        trimUndoStackIfNeeded()
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

    func applyEditorTextEdit(
        _ edit: SourceLineIndexEdit,
        selectedRangeAfter: NSRange,
        completeTextFallback: () -> String
    ) {
        guard let textBufferEdit = textBuffer.replaceCharacters(in: edit.range, with: edit.replacement) else {
            let fallback = completeTextFallback()
            markdown = fallback
            selectedRange = selectedRangeAfter.clamped(toLength: (fallback as NSString).length) ??
                NSRange(location: (fallback as NSString).length, length: 0)
            return
        }

        publishTextBufferSnapshot(using: textBufferEdit)
        selectedRange = selectedRangeAfter.clamped(toLength: textBuffer.length) ??
            NSRange(location: textBuffer.length, length: 0)
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
            markDocumentClean(snapshot: markdown)
            statusMessage = strings.savedFile(url.lastPathComponent)
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func load(contents: String, from url: URL) {
        PerformanceDiagnostics.shared.measure(
            "document.load",
            metadata: [
                "characters": "\((contents as NSString).length)",
                "file_extension": url.pathExtension.isEmpty ? "none" : url.pathExtension,
            ]
        ) {
            setMarkdown(contents, refreshDerivedDataImmediately: true)
        }
        fileURL = url
        selectedRange = NSRange(location: 0, length: 0)
        markDocumentClean(snapshot: contents)
        clearEditingHistory()
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

    func setPerformanceDiagnosticsEnabled(_ enabled: Bool) {
        performanceDiagnosticsEnabled = enabled
        PerformanceDiagnostics.shared.setEnabled(enabled)
        statusMessage = enabled ? strings.enabledPerformanceDiagnostics : strings.disabledPerformanceDiagnostics
    }

    func copyPerformanceReport() {
        let report = performanceReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        statusMessage = strings.copiedPerformanceReport
    }

    func resetPerformanceRecords() {
        PerformanceDiagnostics.shared.reset()
        statusMessage = strings.resetPerformanceRecordsDone
    }

    func performanceReport() -> String {
        PerformanceDiagnostics.shared.snapshot(
            documentName: displayName,
            characterCount: characterCount,
            lineCount: lineCount,
            blockCount: blockIndex.blocks.count,
            outlineCount: outline.count,
            viewMode: viewMode,
            previewTheme: previewTheme
        )
        .lines
        .joined(separator: "\n")
    }

    func jumpToOutlineItem(_ item: OutlineItem) {
        selectedRange = NSRange(location: item.location, length: 0)
        activeOutlineItemID = item.id
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

    func updateActiveOutline(forSourceLine line: Int) {
        activeOutlineSourceLine = max(1, line)
        let nextActiveOutlineItemID = outlineItem(containingSourceLine: activeOutlineSourceLine)?.id
        guard activeOutlineItemID != nextActiveOutlineItemID else {
            return
        }
        activeOutlineItemID = nextActiveOutlineItemID
    }

    private func outlineItem(containingSourceLine line: Int) -> OutlineItem? {
        guard !outline.isEmpty else {
            return nil
        }

        var low = 0
        var high = outline.count - 1
        var matchedIndex: Int?

        while low <= high {
            let mid = (low + high) / 2
            if outline[mid].line <= line {
                matchedIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard let matchedIndex else {
            return nil
        }
        return outline[matchedIndex]
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
        replaceMarkdownCharacters(in: safeRange, with: snippet)

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

    private func applyHistorySnapshot(_ snapshot: String, selection: NSRange?) {
        isApplyingHistory = true
        setMarkdown(snapshot, refreshDerivedDataImmediately: true)
        isApplyingHistory = false
        selectedRange = selection?.clamped(toLength: (markdown as NSString).length)
            ?? selectedRange.clamped(toLength: (markdown as NSString).length)
            ?? NSRange(location: (markdown as NSString).length, length: 0)
        reconcileDirtyStateAfterHistoryChange()
    }

    private enum HistoryEditDirection {
        case undo
        case redo
    }

    private func applyHistoryEdit(_ edit: DocumentEditDelta, direction: HistoryEditDirection) -> Bool {
        let range: NSRange
        let expectedFragment: String
        let replacement: String
        let selection: NSRange

        switch direction {
        case .undo:
            range = edit.newRange
            expectedFragment = edit.newFragment
            replacement = edit.oldFragment
            selection = edit.selectionBefore
        case .redo:
            range = edit.oldRange
            expectedFragment = edit.oldFragment
            replacement = edit.newFragment
            selection = edit.selectionAfter
        }

        guard textBuffer.substring(with: range) == expectedFragment else {
            return applyHistoryEditUsingSnapshotFallback(edit, direction: direction)
        }

        isApplyingHistory = true
        guard let textBufferEdit = textBuffer.replaceCharacters(in: range, with: replacement) else {
            isApplyingHistory = false
            return applyHistoryEditUsingSnapshotFallback(edit, direction: direction)
        }
        publishTextBufferSnapshot(using: textBufferEdit)
        isApplyingHistory = false
        selectedRange = selection.clamped(toLength: textBuffer.length) ??
            NSRange(location: textBuffer.length, length: 0)
        reconcileDirtyStateAfterHistoryChange()
        return true
    }

    private func applyHistoryEditUsingSnapshotFallback(
        _ edit: DocumentEditDelta,
        direction: HistoryEditDirection
    ) -> Bool {
        switch direction {
        case .undo:
            guard let previous = edit.reverting(markdown) else {
                return false
            }
            applyHistorySnapshot(previous, selection: edit.selectionBefore)
            return true
        case .redo:
            guard let next = edit.reapplying(markdown) else {
                return false
            }
            applyHistorySnapshot(next, selection: edit.selectionAfter)
            return true
        }
    }

    private func reconcileDirtyStateAfterHistoryChange() {
        guard markdown.utf16.count == lastSavedSnapshot.utf16.count else {
            return
        }

        if markdown == lastSavedSnapshot {
            savedDocumentRevision = documentRevision
            isDirty = false
        }
    }

    private func replaceMarkdownCharacters(in range: NSRange, with replacement: String) {
        guard let edit = textBuffer.replaceCharacters(in: range, with: replacement) else {
            let nsMarkdown = markdown as NSString
            markdown = nsMarkdown.replacingCharacters(in: range, with: replacement)
            return
        }

        publishTextBufferSnapshot(using: edit)
    }

    private func publishTextBufferSnapshot(using edit: TextBufferEdit) {
        pendingTextBufferEdit = edit
        isPublishingTextBufferSnapshot = true
        markdown = textBuffer.text
        isPublishingTextBufferSnapshot = false
        pendingTextBufferEdit = nil
    }

    private func registerUndoSnapshot(_ previous: String, replacingWith next: String) {
        guard !isApplyingHistory, previous != next else {
            return
        }
        guard let edit = DocumentEditDelta(oldText: previous, newText: next, selectionBefore: selectedRange) else {
            return
        }

        registerUndoDelta(edit)
    }

    private func registerUndoEdit(_ textBufferEdit: TextBufferEdit) {
        guard !isApplyingHistory else {
            return
        }

        registerUndoDelta(DocumentEditDelta(
            textBufferEdit: textBufferEdit,
            selectionBefore: selectedRange
        ))
    }

    private func registerUndoDelta(_ edit: DocumentEditDelta) {
        guard edit.oldFragment != edit.newFragment || edit.oldRange != edit.newRange else {
            return
        }

        let now = Date()
        if
            let lastEdit = undoStack.last,
            let lastUndoRegistrationDate,
            now.timeIntervalSince(lastUndoRegistrationDate) <= Self.undoCoalescingInterval,
            let mergedEdit = lastEdit.merging(with: edit)
        {
            undoMemoryCost -= lastEdit.memoryCost
            undoStack[undoStack.count - 1] = mergedEdit
            undoMemoryCost += mergedEdit.memoryCost
        } else {
            undoStack.append(edit)
            undoMemoryCost += edit.memoryCost
        }
        lastUndoRegistrationDate = now
        trimUndoStackIfNeeded()
        redoStack.removeAll()
        redoMemoryCost = 0
    }

    private func clearEditingHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        undoMemoryCost = 0
        redoMemoryCost = 0
        lastUndoRegistrationDate = nil
    }

    private func trimUndoStackIfNeeded() {
        while undoStack.count > 200 || undoMemoryCost > Self.undoMemoryBudget {
            guard !undoStack.isEmpty else {
                undoMemoryCost = 0
                return
            }
            let removed = undoStack.removeFirst()
            undoMemoryCost -= removed.memoryCost
        }
    }

    private func trimRedoStackIfNeeded() {
        while redoStack.count > 200 || redoMemoryCost > Self.undoMemoryBudget {
            guard !redoStack.isEmpty else {
                redoMemoryCost = 0
                return
            }
            let removed = redoStack.removeFirst()
            redoMemoryCost -= removed.memoryCost
        }
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

    private func makeWorkspaceSearchResults(
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
                let matchingLine = cachedTextContent(for: file)?
                    .firstLine(containing: query)
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

    private func cachedTextContent(for file: WorkspaceFile) -> WorkspaceTextContent? {
        guard !file.isDirectory, file.isTextLike else {
            return nil
        }

        guard
            let values = try? file.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let fileSize = values.fileSize,
            fileSize <= Self.workspaceContentSearchFileSizeLimit
        else {
            return nil
        }

        let modifiedAt = values.contentModificationDate
        if let cached = workspaceTextCache[file.id],
           cached.fileSize == fileSize,
           cached.modifiedAt == modifiedAt {
            return cached.content
        }

        guard let text = try? String(contentsOf: file.url, encoding: .utf8) else {
            return nil
        }

        let content = WorkspaceTextContent(text: text)
        workspaceTextCache[file.id] = WorkspaceTextCacheEntry(
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            content: content
        )
        return content
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
        replaceMarkdownCharacters(in: replaceRange, with: replacement)
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

    private static func scanWorkspaceFiles(in workspaceURL: URL) -> [WorkspaceFile] {
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

private struct DocumentEditDelta: Equatable {
    let oldRange: NSRange
    let newRange: NSRange
    let oldFragment: String
    let newFragment: String
    let selectionBefore: NSRange
    let selectionAfter: NSRange

    private init(
        oldRange: NSRange,
        newRange: NSRange,
        oldFragment: String,
        newFragment: String,
        selectionBefore: NSRange,
        selectionAfter: NSRange
    ) {
        self.oldRange = oldRange
        self.newRange = newRange
        self.oldFragment = oldFragment
        self.newFragment = newFragment
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
    }

    init?(oldText: String, newText: String, selectionBefore: NSRange) {
        guard let edit = MarkdownTextEdit.diff(old: oldText, new: newText) else {
            return nil
        }

        let oldNSString = oldText as NSString
        let newNSString = newText as NSString
        guard NSMaxRange(edit.oldRange) <= oldNSString.length,
              NSMaxRange(edit.newRange) <= newNSString.length else {
            return nil
        }

        oldRange = edit.oldRange
        newRange = edit.newRange
        oldFragment = oldNSString.substring(with: edit.oldRange)
        newFragment = newNSString.substring(with: edit.newRange)
        self.selectionBefore = selectionBefore
        selectionAfter = NSRange(location: edit.newRange.location + edit.newRange.length, length: 0)
    }

    init(textBufferEdit: TextBufferEdit, selectionBefore: NSRange) {
        oldRange = textBufferEdit.oldRange
        newRange = textBufferEdit.newRange
        oldFragment = textBufferEdit.oldFragment
        newFragment = textBufferEdit.newFragment
        self.selectionBefore = selectionBefore
        selectionAfter = NSRange(
            location: textBufferEdit.newRange.location + textBufferEdit.newRange.length,
            length: 0
        )
    }

    var memoryCost: Int {
        (oldFragment as NSString).length * 2 + (newFragment as NSString).length * 2 + 128
    }

    func reverting(_ text: String) -> String? {
        let nsText = text as NSString
        guard NSMaxRange(newRange) <= nsText.length,
              nsText.substring(with: newRange) == newFragment else {
            return nil
        }
        return nsText.replacingCharacters(in: newRange, with: oldFragment)
    }

    func reapplying(_ text: String) -> String? {
        let nsText = text as NSString
        guard NSMaxRange(oldRange) <= nsText.length,
              nsText.substring(with: oldRange) == oldFragment else {
            return nil
        }
        return nsText.replacingCharacters(in: oldRange, with: newFragment)
    }

    func merging(with next: DocumentEditDelta) -> DocumentEditDelta? {
        if let insertion = mergingAdjacentInsertion(with: next) {
            return insertion
        }

        if let forwardDelete = mergingForwardDelete(with: next) {
            return forwardDelete
        }

        if let backspaceDelete = mergingBackspaceDelete(with: next) {
            return backspaceDelete
        }

        return nil
    }

    private func mergingAdjacentInsertion(with next: DocumentEditDelta) -> DocumentEditDelta? {
        guard oldRange.length == 0,
              next.oldRange.length == 0,
              oldFragment.isEmpty,
              next.oldFragment.isEmpty,
              NSMaxRange(newRange) == next.newRange.location else {
            return nil
        }

        return DocumentEditDelta(
            oldRange: oldRange,
            newRange: NSRange(
                location: newRange.location,
                length: newRange.length + next.newRange.length
            ),
            oldFragment: "",
            newFragment: newFragment + next.newFragment,
            selectionBefore: selectionBefore,
            selectionAfter: next.selectionAfter
        )
    }

    private func mergingForwardDelete(with next: DocumentEditDelta) -> DocumentEditDelta? {
        guard newRange.length == 0,
              next.newRange.length == 0,
              newFragment.isEmpty,
              next.newFragment.isEmpty,
              oldRange.location == next.oldRange.location else {
            return nil
        }

        return DocumentEditDelta(
            oldRange: NSRange(
                location: oldRange.location,
                length: oldRange.length + next.oldRange.length
            ),
            newRange: newRange,
            oldFragment: oldFragment + next.oldFragment,
            newFragment: "",
            selectionBefore: selectionBefore,
            selectionAfter: next.selectionAfter
        )
    }

    private func mergingBackspaceDelete(with next: DocumentEditDelta) -> DocumentEditDelta? {
        guard newRange.length == 0,
              next.newRange.length == 0,
              newFragment.isEmpty,
              next.newFragment.isEmpty,
              NSMaxRange(next.oldRange) == oldRange.location else {
            return nil
        }

        return DocumentEditDelta(
            oldRange: NSRange(
                location: next.oldRange.location,
                length: next.oldRange.length + oldRange.length
            ),
            newRange: NSRange(location: next.newRange.location, length: 0),
            oldFragment: next.oldFragment + oldFragment,
            newFragment: "",
            selectionBefore: selectionBefore,
            selectionAfter: next.selectionAfter
        )
    }
}

private struct WorkspaceTextCacheEntry {
    let fileSize: Int
    let modifiedAt: Date?
    let content: WorkspaceTextContent
}

private struct WorkspaceTextContent {
    let text: String

    func firstLine(containing query: String) -> String? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return nil
        }
        guard let matchRange = text.range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        let nsText = text as NSString
        let nsMatchRange = NSRange(matchRange, in: text)
        let lineRange = nsText.lineRange(for: NSRange(location: nsMatchRange.location, length: 0))
        return nsText.substring(with: lineRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
