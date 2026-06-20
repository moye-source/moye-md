import SwiftUI

private enum SidebarLayout {
    static let leadingPadding: CGFloat = 44
    static let trailingPadding: CGFloat = 16
    static let scrollViewTrailingCompensation: CGFloat = 16
}

struct ContentView: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        HSplitView {
            if documentStore.isSidebarVisible {
                SidebarView()
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 500)
            }

            WorkspaceView()
                .frame(minWidth: 720)
        }
        .onAppear {
            NSApplication.shared.windows.first?.identifier = NSUserInterfaceItemIdentifier("editorWindow")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                documentStore.localizeMainMenu()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                documentStore.localizeMainMenu()
            }
        }
        .sheet(isPresented: $documentStore.isQuickOpenPresented) {
            QuickOpenView()
                .environmentObject(documentStore)
        }
    }
}

private struct WorkspaceView: View {
    @EnvironmentObject private var documentStore: DocumentStore
    @State private var editorScrollTarget: SourceLineScrollTarget?
    @State private var previewScrollTarget: SourceLineScrollTarget?
    @State private var scrollSyncRevision = 0
    @State private var mutedScrollSource: ScrollSyncSource?

    var body: some View {
        VStack(spacing: 0) {
            if documentStore.viewMode != .preview {
                EditorInsertToolbar()
                Divider()
            }

            if documentStore.viewMode == .split {
                HSplitView {
                    editorPane
                        .frame(minWidth: 360)
                    previewPane
                        .frame(minWidth: 360)
                }
            } else if documentStore.viewMode == .editor {
                editorPane
            } else {
                previewPane
            }

            Divider()
            EditorStatusBar()
        }
        .onChange(of: documentStore.editorNavigationTarget) { target in
            applyEditorNavigationTarget(target)
        }
    }

    private var editorPane: some View {
        MarkdownEditorView(
            text: $documentStore.markdown,
            selectedRange: $documentStore.selectedRange,
            contentRevision: documentStore.documentRevision,
            focusModeEnabled: documentStore.focusModeEnabled,
            typewriterModeEnabled: documentStore.typewriterModeEnabled,
            lineNumbersEnabled: documentStore.lineNumbersEnabled,
            autoPairEnabled: documentStore.autoPairEnabled,
            scrollTarget: editorScrollTarget,
            onTextEdit: documentStore.applyEditorTextEdit,
            onVisibleSourceLineChange: syncEditorToPreview,
            onInsertImageURLs: documentStore.insertImageURLs,
            onPasteImage: documentStore.insertImageFromPasteboard
        )
        .frame(minWidth: 360)
    }

    private var previewPane: some View {
        MarkdownPreviewView(
            markdown: documentStore.markdown,
            contentRevision: documentStore.documentRevision,
            baseURL: documentStore.baseURL,
            theme: documentStore.previewTheme,
            scrollTarget: previewScrollTarget,
            onVisibleSourceLineChange: syncPreviewToEditor
        )
        .frame(minWidth: 360)
    }

    private func syncEditorToPreview(_ line: Int) {
        guard mutedScrollSource != .editor else {
            return
        }

        DispatchQueue.main.async {
            documentStore.updateActiveOutline(forSourceLine: line)
        }

        guard documentStore.viewMode == .split else {
            return
        }

        DispatchQueue.main.async {
            scrollSyncRevision += 1
            mutedScrollSource = .preview
            previewScrollTarget = SourceLineScrollTarget(line: max(1, line), revision: scrollSyncRevision)
            clearMutedScrollSource(.preview)
        }
    }

    private func syncPreviewToEditor(_ line: Int) {
        guard mutedScrollSource != .preview else {
            return
        }

        DispatchQueue.main.async {
            documentStore.updateActiveOutline(forSourceLine: line)
        }

        guard documentStore.viewMode == .split else {
            return
        }

        DispatchQueue.main.async {
            scrollSyncRevision += 1
            mutedScrollSource = .editor
            editorScrollTarget = SourceLineScrollTarget(line: max(1, line), revision: scrollSyncRevision)
            clearMutedScrollSource(.editor)
        }
    }

    private func clearMutedScrollSource(_ source: ScrollSyncSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard mutedScrollSource == source else {
                return
            }
            mutedScrollSource = nil
        }
    }

    private func applyEditorNavigationTarget(_ target: SourceLineScrollTarget?) {
        guard let target else {
            return
        }

        scrollSyncRevision += 1
        mutedScrollSource = .editor
        let routedTarget = SourceLineScrollTarget(
            line: max(1, target.line),
            revision: scrollSyncRevision,
            location: target.location,
            anchorID: target.anchorID
        )

        if documentStore.viewMode != .editor {
            previewScrollTarget = routedTarget
        }
        if documentStore.viewMode != .preview {
            editorScrollTarget = routedTarget
        }
        clearMutedScrollSource(.editor)
    }
}

private enum ScrollSyncSource {
    case editor
    case preview
}

private struct EditorInsertToolbar: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        let strings = documentStore.strings

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                IconToolbarButton(title: strings.undo, systemImage: "arrow.uturn.backward") {
                    documentStore.undoEditing()
                }
                .disabled(!documentStore.canUndo)

                IconToolbarButton(title: strings.redo, systemImage: "arrow.uturn.forward") {
                    documentStore.redoEditing()
                }
                .disabled(!documentStore.canRedo)

                Divider()
                    .frame(height: 20)

                ToolbarButton(title: strings.heading, systemImage: "textformat.size") {
                    documentStore.insertHeading()
                }
                ToolbarButton(title: strings.toc, systemImage: "list.bullet.indent") {
                    documentStore.insertTableOfContents()
                }

                Menu {
                    ForEach(CodeTemplate.common) { template in
                        Button {
                            documentStore.insertCodeTemplate(template)
                        } label: {
                            Label(template.title, systemImage: template.systemImage)
                        }
                    }
                } label: {
                    Label(strings.code, systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(strings.codeTemplate)

                Menu {
                    Button {
                        documentStore.insertTable()
                    } label: {
                        Label(strings.insertTable, systemImage: "tablecells")
                    }

                    Divider()

                    Button {
                        documentStore.insertTableRowAbove()
                    } label: {
                        Label(strings.addRowAbove, systemImage: "arrow.up.to.line.compact")
                    }

                    Button {
                        documentStore.insertTableRowBelow()
                    } label: {
                        Label(strings.addRowBelow, systemImage: "arrow.down.to.line.compact")
                    }

                    Button {
                        documentStore.deleteCurrentTableRows()
                    } label: {
                        Label(strings.deleteRow, systemImage: "minus.rectangle")
                    }

                    Divider()

                    Button {
                        documentStore.insertTableColumnLeft()
                    } label: {
                        Label(strings.addColumnLeft, systemImage: "arrow.left.to.line.compact")
                    }

                    Button {
                        documentStore.insertTableColumnRight()
                    } label: {
                        Label(strings.addColumnRight, systemImage: "arrow.right.to.line.compact")
                    }

                    Button {
                        documentStore.deleteCurrentTableColumn()
                    } label: {
                        Label(strings.deleteColumn, systemImage: "minus.square")
                    }

                    Divider()

                    Button {
                        documentStore.formatCurrentTable()
                    } label: {
                        Label(strings.formatTable, systemImage: "wand.and.stars")
                    }
                } label: {
                    Label(strings.table, systemImage: "tablecells")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(strings.table)

                ToolbarButton(title: strings.tasks, systemImage: "checklist") {
                    documentStore.insertTaskList()
                }
                ToolbarButton(title: strings.image, systemImage: "photo") {
                    documentStore.insertImage()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EditorStatusBar: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        let strings = documentStore.strings

        HStack(spacing: 14) {
            Text(documentStore.statusMessage)
                .lineLimit(1)

            Spacer()

            StatusMetric(label: strings.status, value: documentStore.dirtyIndicator)
            StatusMetric(label: strings.words, value: "\(documentStore.wordCount)")
            StatusMetric(label: strings.characters, value: "\(documentStore.characterCount)")
            StatusMetric(label: strings.lines, value: "\(documentStore.lineCount)")
            StatusMetric(label: strings.readTime, value: strings.minutes(documentStore.readingMinutes))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        let strings = documentStore.strings

        ZStack(alignment: .topLeading) {
            MacSidebarBackground()

            HStack(spacing: 0) {
                Color.clear
                    .frame(width: SidebarLayout.leadingPadding)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(documentStore.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(2)

                        Text(documentStore.dirtyIndicator)
                            .font(.system(size: 13))
                            .foregroundStyle(documentStore.isDirty ? .orange : .secondary)

                        if documentStore.isDirty {
                            Label(strings.unsavedChangesVisible, systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                    }

                    Picker(strings.sidebarContent, selection: Binding(
                        get: { documentStore.sidebarPanel },
                        set: { documentStore.setSidebarPanel($0) }
                    )) {
                        ForEach(SidebarPanel.allCases) { panel in
                            Text(strings.sidebarPanelTitle(panel)).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.regular)

                    Divider()

                    Group {
                        switch documentStore.sidebarPanel {
                        case .files:
                            WorkspaceFilesPanel()
                        case .outline:
                            OutlinePanel()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.trailing, SidebarLayout.trailingPadding)
                .padding(.vertical, 18)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        let strings = documentStore.strings

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(strings.settingsTitle)
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            Divider()

            Form {
                Section(strings.general) {
                    Picker(strings.interfaceLanguage, selection: Binding(
                        get: { documentStore.language },
                        set: { documentStore.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(strings.languageTitle(language)).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(strings.view) {
                    Picker(strings.viewMode, selection: Binding(
                        get: { documentStore.viewMode },
                        set: { documentStore.setViewMode($0) }
                    )) {
                        ForEach(EditorViewMode.allCases) { mode in
                            Label(strings.viewModeTitle(mode), systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(strings.theme, selection: Binding(
                        get: { documentStore.previewTheme },
                        set: { documentStore.setPreviewTheme($0) }
                    )) {
                        ForEach(PreviewTheme.allCases) { theme in
                            Text(strings.previewThemeTitle(theme)).tag(theme)
                        }
                    }
                }

                Section(strings.editor) {
                    Toggle(strings.focus, isOn: $documentStore.focusModeEnabled)
                    Toggle(strings.typewriter, isOn: $documentStore.typewriterModeEnabled)
                    Toggle(strings.lineNumbers, isOn: $documentStore.lineNumbersEnabled)
                    Toggle(strings.autoPair, isOn: $documentStore.autoPairEnabled)
                }

                Section(strings.assets) {
                    Toggle(strings.copyToAssets, isOn: $documentStore.copyImagesToAssetFolder)
                }

                Section(strings.performance) {
                    Toggle(strings.performanceDiagnostics, isOn: Binding(
                        get: { documentStore.performanceDiagnosticsEnabled },
                        set: { documentStore.setPerformanceDiagnosticsEnabled($0) }
                    ))

                    Text(strings.performanceDiagnosticsHelp)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(strings.copyPerformanceReport) {
                            documentStore.copyPerformanceReport()
                        }
                        .disabled(!documentStore.performanceDiagnosticsEnabled)

                        Button(strings.resetPerformanceRecords) {
                            documentStore.resetPerformanceRecords()
                        }
                        .disabled(!documentStore.performanceDiagnosticsEnabled)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct WorkspaceFilesPanel: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        let strings = documentStore.strings
        let isSearching = !documentStore.fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let searchResults = documentStore.workspaceSearchResults
        let visibleRows = documentStore.visibleWorkspaceTreeRows

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SidebarSectionHeader(title: strings.files, detail: documentStore.workspaceTitle)

                Spacer()
            }

            TextField(strings.searchFilesAndContent, text: $documentStore.fileSearchQuery)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .controlSize(.regular)

            if documentStore.workspaceURL == nil {
                SidebarEmptyState(
                    title: strings.openFolderHelp,
                    message: strings.openFolderPrompt,
                    systemImage: "folder.badge.plus"
                )
            } else if isSearching, searchResults.isEmpty {
                SidebarEmptyState(
                    title: strings.noMatchingFiles,
                    message: strings.searchFilesAndContent,
                    systemImage: "magnifyingglass"
                )
            } else if !isSearching, visibleRows.isEmpty {
                SidebarEmptyState(
                    title: strings.noMatchingFiles,
                    message: documentStore.workspaceTitle,
                    systemImage: "tray"
                )
            } else {
                SidebarScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if isSearching {
                            ForEach(searchResults) { result in
                                Button {
                                    documentStore.openWorkspaceFile(result.file)
                                } label: {
                                    WorkspaceFileResultRow(result: result)
                                        .environmentObject(documentStore)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    WorkspaceFileContextMenu(file: result.file)
                                        .environmentObject(documentStore)
                                }
                            }
                        } else {
                            ForEach(visibleRows) { row in
                                Button {
                                    documentStore.openWorkspaceFile(row.file)
                                } label: {
                                    WorkspaceTreeFileRow(row: row)
                                        .environmentObject(documentStore)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 180, maxHeight: .infinity)
                .contextMenu {
                    WorkspaceFileContextMenu(file: nil)
                        .environmentObject(documentStore)
                }
            }
        }
    }
}

private struct WorkspaceTreeFileRow: View {
    @EnvironmentObject private var documentStore: DocumentStore
    let row: WorkspaceTreeRow

    var body: some View {
        let file = row.file
        let icon = MaterialFileIconProvider.icon(for: file)
        let isExpanded = file.isDirectory && documentStore.isWorkspaceDirectoryExpanded(file)
        let isSelected = documentStore.selectedWorkspaceFileID == file.id

        HStack(spacing: 9) {
            if file.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            } else {
                Color.clear
                    .frame(width: 14)
            }

            Image(systemName: icon.systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(icon.color)
                .frame(width: 20)

            Text(file.displayName)
                .font(.system(size: 15))
                .lineLimit(1)
                .foregroundStyle(file.isDirectory || file.isTextLike ? .primary : .secondary)
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SidebarSourceRowBackground(isSelected: isSelected))
        .contentShape(Rectangle())
        .help(file.relativePath)
        .contextMenu {
            WorkspaceFileContextMenu(file: file)
                .environmentObject(documentStore)
        }
    }
}

private struct WorkspaceFileContextMenu: View {
    @EnvironmentObject private var documentStore: DocumentStore
    let file: WorkspaceFile?

    var body: some View {
        let strings = documentStore.strings

        Button(strings.newWorkspaceFile) {
            documentStore.createWorkspaceFile(in: file)
        }

        Button(strings.newWorkspaceFolder) {
            documentStore.createWorkspaceFolder(in: file)
        }

        if let file {
            Divider()

            Button(strings.renameWorkspaceItem) {
                documentStore.renameWorkspaceItem(file)
            }

            Button(strings.moveWorkspaceItemToTrash) {
                documentStore.moveWorkspaceItemToTrash(file)
            }
        }
    }
}

private struct QuickOpenView: View {
    @EnvironmentObject private var documentStore: DocumentStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        let strings = documentStore.strings
        let results = Array(documentStore.quickOpenResults.prefix(80))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.quickOpenTitle)
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    documentStore.dismissQuickOpen()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(strings.cancel)
            }

            TextField(strings.quickOpenPlaceholder, text: $documentStore.quickOpenQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit {
                    if let firstResult = results.first {
                        documentStore.openQuickOpenResult(firstResult)
                    }
                }

            if documentStore.workspaceURL == nil {
                Text(strings.openFolderPrompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if results.isEmpty {
                Text(strings.noMatchingFiles)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(results) { result in
                            Button {
                                documentStore.openQuickOpenResult(result)
                            } label: {
                                WorkspaceFileResultRow(result: result)
                                    .environmentObject(documentStore)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .frame(width: 580, height: 420)
        .onAppear {
            searchFocused = true
        }
    }
}

private struct WorkspaceFileResultRow: View {
    @EnvironmentObject private var documentStore: DocumentStore
    let result: WorkspaceSearchResult

    var body: some View {
        let icon = MaterialFileIconProvider.icon(for: result.file)
        let strings = documentStore.strings

        let isSelected = documentStore.selectedWorkspaceFileID == result.file.id

        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon.systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(icon.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.file.relativePath)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let snippet = result.snippet, !snippet.isEmpty {
                    HStack(spacing: 4) {
                        Text(matchLabel(result.matchKind, strings: strings))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(snippet)
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SidebarSourceRowBackground(isSelected: isSelected))
    }

    private func matchLabel(_ kind: WorkspaceMatchKind, strings: LocalizedStrings) -> String {
        switch kind {
        case .path:
            strings.pathMatch
        case .fileName:
            strings.fileNameMatch
        case .content:
            strings.contentMatch
        }
    }
}

private struct MaterialFileIcon {
    let systemName: String
    let color: Color
}

private enum MaterialFileIconProvider {
    static func icon(for file: WorkspaceFile) -> MaterialFileIcon {
        if file.isDirectory {
            return MaterialFileIcon(systemName: "folder.fill", color: .accentColor)
        }

        let name = file.displayName.lowercased()
        let ext = file.url.pathExtension.lowercased()

        if ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock"].contains(name) {
            return MaterialFileIcon(systemName: "shippingbox.fill", color: .orange)
        }
        if ["dockerfile", "docker-compose.yml", "docker-compose.yaml"].contains(name) {
            return MaterialFileIcon(systemName: "shippingbox", color: .cyan)
        }
        if ["makefile", "justfile"].contains(name) {
            return MaterialFileIcon(systemName: "hammer.fill", color: .yellow)
        }
        if ["nginx.conf", "default.conf"].contains(name) {
            return MaterialFileIcon(systemName: "network", color: .green)
        }

        switch ext {
        case "md", "markdown":
            return MaterialFileIcon(systemName: "doc.richtext", color: .blue)
        case "swift":
            return MaterialFileIcon(systemName: "curlybraces", color: .orange)
        case "js", "jsx", "ts", "tsx":
            return MaterialFileIcon(systemName: "curlybraces.square", color: .yellow)
        case "vue", "svelte":
            return MaterialFileIcon(systemName: "diamond", color: .green)
        case "html", "htm":
            return MaterialFileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .orange)
        case "css", "scss", "sass", "less":
            return MaterialFileIcon(systemName: "paintbrush.pointed", color: .blue)
        case "json":
            return MaterialFileIcon(systemName: "curlybraces.square.fill", color: .yellow)
        case "yml", "yaml", "toml":
            return MaterialFileIcon(systemName: "list.bullet.rectangle", color: .purple)
        case "sh", "bash", "zsh":
            return MaterialFileIcon(systemName: "terminal.fill", color: .green)
        case "py":
            return MaterialFileIcon(systemName: "terminal", color: .yellow)
        case "sql":
            return MaterialFileIcon(systemName: "cylinder.split.1x2", color: .teal)
        case "png", "jpg", "jpeg", "gif", "webp", "svg":
            return MaterialFileIcon(systemName: "photo", color: .pink)
        default:
            return MaterialFileIcon(systemName: "doc.text", color: .secondary)
        }
    }
}

private struct OutlinePanel: View {
    @EnvironmentObject private var documentStore: DocumentStore

    var body: some View {
        let strings = documentStore.strings

        VStack(alignment: .leading, spacing: 12) {
            SidebarSectionHeader(title: strings.outline, detail: "\(documentStore.outline.count)")

            if documentStore.outline.isEmpty {
                SidebarEmptyState(
                    title: strings.noHeadings,
                    message: strings.outline,
                    systemImage: "list.bullet.indent"
                )
            } else {
                SidebarScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(documentStore.outline) { item in
                            Button {
                                documentStore.jumpToOutlineItem(item)
                            } label: {
                                OutlineSourceRow(
                                    item: item,
                                    isActive: documentStore.activeOutlineItemID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SidebarScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .padding(.trailing, SidebarLayout.scrollViewTrailingCompensation)
                .background(SidebarScrollerConfigurator())
        }
        .padding(.trailing, -SidebarLayout.scrollViewTrailingCompensation)
    }
}

private struct SidebarScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else {
                return
            }

            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = .clear
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
            scrollView.verticalScroller?.controlSize = .mini
        }
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

private struct SidebarEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.horizontal, 14)
    }
}

private struct SidebarSourceRowBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
    }
}

private struct OutlineSourceRow: View {
    let item: OutlineItem
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text("H\(item.level)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.white.opacity(0.82) : .secondary)
                .frame(width: 30, alignment: .leading)

            Text(item.title)
                .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(max(0, item.level - 1)) * 18)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutlineRowBackground(isActive: isActive, isHovered: isHovered))
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 18)
                    .padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct OutlineRowBackground: View {
    let isActive: Bool
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(isHovered ? 0.92 : 0.82)
        }
        if isHovered {
            return Color.primary.opacity(0.07)
        }
        return .clear
    }
}

private struct MacSidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .withinWindow
        nsView.state = .active
    }
}

private struct ToolbarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
    }
}

private struct IconToolbarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct StatusMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Text(value)
                .monospacedDigit()
        }
    }
}
