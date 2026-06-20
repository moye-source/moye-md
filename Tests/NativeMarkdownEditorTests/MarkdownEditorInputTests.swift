import AppKit
import WebKit
import XCTest
@testable import NativeMarkdownEditor

@MainActor
final class MarkdownEditorInputTests: XCTestCase {
    func testSelectionRangesClampAfterExternalTextShrink() {
        let selectedRanges = [NSValue(range: NSRange(location: 11, length: 0))]
        let clamped = selectedRanges.clampedSelectionRanges(
            toLength: 0,
            fallback: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(clamped.count, 1)
        XCTAssertEqual(clamped.first?.rangeValue, NSRange(location: 0, length: 0))
    }

    func testEditorDocumentHeightStaysTightAtBottomScrollLimit() throws {
        let markdown = (1...180)
            .map { index in
                index.isMultiple(of: 12) ? "## Section \(index)" : "Line \(index)"
            }
            .joined(separator: "\n")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = markdown
        scrollView.documentView = textView

        MarkdownSyntaxHighlighter.apply(to: textView)
        MarkdownEditorView.updateTextContainerGeometry(for: scrollView, textView: textView)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)

        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let expectedDocumentHeight = max(
            scrollView.contentSize.height,
            ceil(usedHeight + textView.textContainerInset.height * 2 + 4)
        )
        let trailingBlankHeight = textView.frame.height - (usedHeight + textView.textContainerInset.height * 2)

        XCTAssertLessThanOrEqual(textView.frame.height, expectedDocumentHeight + 8)
        XCTAssertLessThanOrEqual(trailingBlankHeight, 12)

        let bottomY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertLessThanOrEqual(scrollView.contentView.bounds.maxY, textView.frame.height + 1)
    }

    func testEditorVisibleSourceLineTracksScrolledGlyphPosition() throws {
        let markdown = (1...240)
            .map { "Line \($0) alpha beta gamma delta epsilon" }
            .joined(separator: "\n")
        let sourceLineIndex = SourceLineIndex(text: markdown)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 260))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 260))
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.string = markdown
        scrollView.documentView = textView

        MarkdownEditorView.updateTextContainerGeometry(for: scrollView, textView: textView)

        let targetRange = sourceLineIndex.range(forLine: 120)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: targetRange, actualCharacterRange: nil)
        let targetRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetRect.minY))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let visibleLine = MarkdownEditorView.visibleSourceLine(in: textView, sourceLineIndex: sourceLineIndex)

        XCTAssertGreaterThanOrEqual(visibleLine, 119)
        XCTAssertLessThanOrEqual(visibleLine, 122)
    }

    func testEditorTextContainerLeavesTrailingRoomForOverlayScroller() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = "这份默认文档用于检查常见 Markdown 语法、开发代码块、运维配置和图片预览。"
        scrollView.documentView = textView

        MarkdownEditorView.updateTextContainerGeometry(for: scrollView, textView: textView)

        let textContainer = try XCTUnwrap(textView.textContainer)
        let availableWidthBeforeScroller = scrollView.contentSize.width - 12
        let occupiedLineWidth = textContainer.containerSize.width + textView.textContainerInset.width * 2

        XCTAssertFalse(textContainer.widthTracksTextView)
        XCTAssertLessThanOrEqual(occupiedLineWidth, availableWidthBeforeScroller)
    }

    func testEditorConfiguresLargeTextLayoutForDemandDrivenRendering() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))

        MarkdownEditorView.configureLargeTextLayout(for: textView)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        XCTAssertTrue(layoutManager.allowsNonContiguousLayout)
        XCTAssertFalse(layoutManager.backgroundLayoutEnabled)
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isGrammarCheckingEnabled)
        XCTAssertFalse(textView.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticDataDetectionEnabled)
    }

    func testLargeDocumentStatisticsHandle150kWords() {
        let markdown = Self.largeMarkdown(paragraphCount: 15_000)
        let statistics = MarkdownBlockIndex(markdown: markdown).statistics

        XCTAssertGreaterThanOrEqual(statistics.wordCount, 150_000)
        XCTAssertGreaterThan(statistics.characterCount, 900_000)
        XCTAssertGreaterThan(statistics.lineCount, 20_000)
    }

    func testDocumentStatisticsPreservesSplitSemanticsWithoutAllocatingLineArrays() {
        XCTAssertEqual(DocumentStatistics(markdown: ""), .empty)

        let statistics = DocumentStatistics(markdown: "alpha\n\nbeta gamma\n")

        XCTAssertEqual(statistics.wordCount, 3)
        XCTAssertEqual(statistics.characterCount, 18)
        XCTAssertEqual(statistics.lineCount, 4)
    }

    func testSourceLineIndexMapsVisibleCharacterPositions() {
        let markdown = "alpha\nbeta\n# Gamma\nlast"
        let index = SourceLineIndex(text: markdown)

        XCTAssertEqual(index.lineCount, 4)
        XCTAssertEqual(index.characterCount, (markdown as NSString).length)
        XCTAssertEqual(index.lineNumber(at: 0), 1)
        XCTAssertEqual(index.lineNumber(at: 6), 2)
        XCTAssertEqual(index.lineNumber(at: (markdown as NSString).range(of: "# Gamma").location), 3)
        XCTAssertEqual(index.lineNumber(at: (markdown as NSString).length), 4)
        XCTAssertEqual((markdown as NSString).substring(with: index.range(forLine: 3)), "# Gamma\n")
    }

    func testSourceLineIndexEstimatesWrappedVisualLinesWithoutScanningTextAgain() {
        let markdown = "short\n1234567890\n12345678901\n"
        let index = SourceLineIndex(text: markdown)

        XCTAssertEqual(index.estimatedVisualLineCount(charactersPerVisualLine: 10), 5)
    }

    func testSourceLineIndexCarriesEstimatedVisualLineCacheAcrossLocalizedEdit() throws {
        let markdown = (1...1_000)
            .map { "Line \($0) alpha beta gamma delta epsilon" }
            .joined(separator: "\n")
        let index = SourceLineIndex(text: markdown)
        let initialVisualLines = index.estimatedVisualLineCount(charactersPerVisualLine: 16)

        XCTAssertGreaterThan(initialVisualLines, 1_000)
        XCTAssertEqual(index.cachedEstimatedVisualLineCountWidthCountForTesting, 1)

        let editRange = (markdown as NSString).range(of: "Line 500 alpha")
        let editedMarkdown = (markdown as NSString).replacingCharacters(
            in: editRange,
            with: "Line 500 alpha\ninserted wrapping words"
        )
        let updatedIndex = try XCTUnwrap(index.updating(
            with: SourceLineIndexEdit(
                range: editRange,
                replacement: "Line 500 alpha\ninserted wrapping words"
            ),
            newTextLength: (editedMarkdown as NSString).length
        ))
        let fullIndex = SourceLineIndex(text: editedMarkdown)

        XCTAssertEqual(updatedIndex.cachedEstimatedVisualLineCountWidthCountForTesting, 1)
        XCTAssertEqual(
            updatedIndex.estimatedVisualLineCount(charactersPerVisualLine: 16),
            fullIndex.estimatedVisualLineCount(charactersPerVisualLine: 16)
        )
    }

    func testSourceLineIndexAppliesIncrementalLineEdits() throws {
        let markdown = "alpha\nbeta\ngamma"
        let nsMarkdown = markdown as NSString
        let insertion = "\ninserted"
        let insertionRange = NSRange(location: nsMarkdown.range(of: "beta").location + 4, length: 0)
        let insertedMarkdown = nsMarkdown.replacingCharacters(in: insertionRange, with: insertion)
        let insertedIndex = try XCTUnwrap(
            SourceLineIndex(text: markdown).updating(
                with: SourceLineIndexEdit(range: insertionRange, replacement: insertion),
                newTextLength: (insertedMarkdown as NSString).length
            )
        )

        XCTAssertEqual(insertedIndex, SourceLineIndex(text: insertedMarkdown))
        XCTAssertEqual(insertedIndex.lineCount, 4)

        let deletionRange = (insertedMarkdown as NSString).range(of: "\ninserted")
        let deletedMarkdown = (insertedMarkdown as NSString).replacingCharacters(in: deletionRange, with: "")
        let deletedIndex = try XCTUnwrap(
            insertedIndex.updating(
                with: SourceLineIndexEdit(range: deletionRange, replacement: ""),
                newTextLength: (deletedMarkdown as NSString).length
            )
        )

        XCTAssertEqual(deletedIndex, SourceLineIndex(text: deletedMarkdown))
        XCTAssertEqual(deletedIndex.lineCount, 3)
    }

    func testSourceLineIndexAppliesIncrementalMultilineReplacement() throws {
        let markdown = "one\ntwo\nthree"
        let replacementRange = (markdown as NSString).range(of: "two")
        let replacement = "2a\n2b"
        let replacedMarkdown = (markdown as NSString).replacingCharacters(in: replacementRange, with: replacement)
        let updatedIndex = try XCTUnwrap(
            SourceLineIndex(text: markdown).updating(
                with: SourceLineIndexEdit(range: replacementRange, replacement: replacement),
                newTextLength: (replacedMarkdown as NSString).length
            )
        )

        XCTAssertEqual(updatedIndex, SourceLineIndex(text: replacedMarkdown))
        XCTAssertEqual(updatedIndex.lineCount, 4)
        XCTAssertEqual((replacedMarkdown as NSString).substring(with: updatedIndex.range(forLine: 3)), "2b\n")
    }

    func testPieceTableTextBufferAppliesLocalizedEditsAndLineIndex() throws {
        let buffer = PieceTableTextBuffer("alpha\nbeta\ngamma")
        let range = ("alpha\nbeta\ngamma" as NSString).range(of: "beta")
        let edit = try XCTUnwrap(buffer.replaceCharacters(in: range, with: "b1\nb2"))

        XCTAssertEqual(buffer.text, "alpha\nb1\nb2\ngamma")
        XCTAssertEqual(buffer.length, ("alpha\nb1\nb2\ngamma" as NSString).length)
        XCTAssertEqual(buffer.lineIndex.lineCount, 4)
        XCTAssertEqual(buffer.lineIndex.lineNumber(at: ("alpha\nb1\nb2\ngamma" as NSString).range(of: "gamma").location), 4)
        XCTAssertEqual(edit.oldFragment, "beta")
        XCTAssertEqual(edit.newFragment, "b1\nb2")
        XCTAssertEqual(edit.lineDelta, 1)
        XCTAssertGreaterThanOrEqual(buffer.pieceCount, 2)
    }

    func testPieceTableTextBufferCoalescesAdjacentAddPieces() throws {
        let buffer = PieceTableTextBuffer("base")

        _ = try XCTUnwrap(buffer.replaceCharacters(in: NSRange(location: 4, length: 0), with: " A"))
        _ = try XCTUnwrap(buffer.replaceCharacters(in: NSRange(location: 6, length: 0), with: " B"))

        XCTAssertEqual(buffer.text, "base A B")
        XCTAssertLessThanOrEqual(buffer.pieceCount, 2)
    }

    func testMarkdownTextEditTracksLineDeltaForLocalizedChanges() throws {
        let insertedLine = try XCTUnwrap(MarkdownTextEdit.diff(old: "alpha\nbeta", new: "alpha\ninserted\nbeta"))
        let removedLine = try XCTUnwrap(MarkdownTextEdit.diff(old: "alpha\ninserted\nbeta", new: "alpha\nbeta"))
        let sameLineEdit = try XCTUnwrap(MarkdownTextEdit.diff(old: "alpha beta", new: "alpha edited beta"))

        XCTAssertEqual(insertedLine.lineDelta, 1)
        XCTAssertEqual(removedLine.lineDelta, -1)
        XCTAssertEqual(sameLineEdit.lineDelta, 0)
    }

    func testMarkdownBlockIndexParsesOutlineAndCommonBlockTypes() {
        let markdown = """
        # Title

        Intro paragraph.

        | A | B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        print("hello")
        ```
        """
        let index = MarkdownBlockIndex(markdown: markdown)

        XCTAssertEqual(index.outline.map(\.title), ["Title"])
        XCTAssertTrue(index.blocks.contains { $0.type == .heading(level: 1) })
        XCTAssertTrue(index.blocks.contains { $0.type == .paragraph })
        XCTAssertTrue(index.blocks.contains { $0.type == .table })
        XCTAssertTrue(index.blocks.contains { $0.type == .codeFence(language: "swift") })
    }

    func testMarkdownBlockIndexReusesUnaffectedBlocksAfterLocalEdit() throws {
        let markdown = """
        # A

        First paragraph.

        ## B

        Second paragraph.
        """
        let index = MarkdownBlockIndex(markdown: markdown)
        let unaffectedBlockID = try XCTUnwrap(index.blocks.last?.id)
        let editedMarkdown = markdown.replacingOccurrences(of: "First paragraph.", with: "First paragraph edited.")
        let edit = try XCTUnwrap(MarkdownTextEdit.diff(old: markdown, new: editedMarkdown))
        let nextIndex = index.updating(markdown: editedMarkdown, edit: edit, revision: 1)

        XCTAssertEqual(nextIndex.outline.map(\.title), ["A", "B"])
        XCTAssertEqual(nextIndex.blocks.last?.id, unaffectedBlockID)
        XCTAssertTrue(nextIndex.blocks.contains { $0.source.contains("First paragraph edited.") })
    }

    func testMarkdownBlockIndexIncrementalStatisticsMatchFullParseForLargeLocalEdit() throws {
        let markdown = Self.largeMarkdown(paragraphCount: 4_000)
        let index = MarkdownBlockIndex(markdown: markdown)
        let editedMarkdown = markdown.replacingOccurrences(
            of: "Paragraph 1777 alpha beta gamma",
            with: "Paragraph 1777 alpha beta gamma edited words"
        )
        let edit = try XCTUnwrap(MarkdownTextEdit.diff(old: markdown, new: editedMarkdown))

        let nextIndex = index.updating(markdown: editedMarkdown, edit: edit, revision: 1)
        let fullIndex = MarkdownBlockIndex(markdown: editedMarkdown, revision: 1)

        XCTAssertEqual(nextIndex.statistics, fullIndex.statistics)
        XCTAssertEqual(nextIndex.outline.map(\.title), fullIndex.outline.map(\.title))
        XCTAssertEqual(nextIndex.outline.map(\.level), fullIndex.outline.map(\.level))
        XCTAssertEqual(nextIndex.outline.map(\.line), fullIndex.outline.map(\.line))
        XCTAssertEqual(nextIndex.outline.map(\.location), fullIndex.outline.map(\.location))
    }

    func testDocumentStoreSynchronizesDerivedDataFromBlockIndex() {
        let store = DocumentStore()
        store.markdown = """
        # Alpha

        Body

        ## Beta
        """

        XCTAssertEqual(store.outline.map(\.title), store.blockIndex.outline.map(\.title))
        XCTAssertEqual(store.statistics, store.blockIndex.statistics)
        XCTAssertEqual(store.outline.map(\.title), ["Alpha", "Beta"])
    }

    func testDocumentStoreTracksActiveOutlineItemFromVisibleSourceLine() {
        let store = DocumentStore()
        store.markdown = """
        Intro

        # Alpha

        Body

        ## Beta

        Details
        """

        store.updateActiveOutline(forSourceLine: 1)
        XCTAssertNil(store.activeOutlineItemID)

        store.updateActiveOutline(forSourceLine: 5)
        XCTAssertEqual(store.activeOutlineItemID, store.outline[0].id)

        store.updateActiveOutline(forSourceLine: 9)
        XCTAssertEqual(store.activeOutlineItemID, store.outline[1].id)
    }

    func testPerformanceDiagnosticsIsEnabledByDefaultAndReportsLogPath() {
        let store = DocumentStore()

        XCTAssertTrue(store.performanceDiagnosticsEnabled)
        XCTAssertTrue(PerformanceDiagnostics.shared.isEnabled)

        let report = store.performanceReport()

        XCTAssertTrue(report.contains("diagnostics_enabled: true"))
        XCTAssertTrue(report.contains("diagnostic_log_path:"))

        store.setPerformanceDiagnosticsEnabled(false)
    }

    func testPerformanceDiagnosticsReportDoesNotIncludeDocumentBody() {
        let store = DocumentStore()
        store.markdown = """
        # Private Heading

        private body text should stay out of diagnostics
        """
        store.setPerformanceDiagnosticsEnabled(true)
        PerformanceDiagnostics.shared.record(
            "test.event",
            durationMilliseconds: 12.3,
            metadata: ["characters": "\(store.characterCount)"]
        )

        let report = store.performanceReport()

        XCTAssertTrue(report.contains("Moye Performance Report"))
        XCTAssertTrue(report.contains("characters:"))
        XCTAssertTrue(report.contains("test.event"))
        XCTAssertFalse(report.contains("Private Heading"))
        XCTAssertFalse(report.contains("private body text"))

        store.setPerformanceDiagnosticsEnabled(false)
    }

    func testLargeDocumentsUseDebouncedPreviewAndSkipFullHighlighting() {
        let mediumMarkdown = String(repeating: "Paragraph alpha beta gamma.\n", count: 3_400)
        let veryLargeMarkdown = String(repeating: "Paragraph alpha beta gamma.\n", count: 25_000)
        let massiveMarkdown = String(repeating: "Paragraph alpha beta gamma.\n", count: 42_000)
        let markdown = Self.largeMarkdown(paragraphCount: 15_000)

        XCTAssertTrue(MarkdownPreviewView.usesBackgroundRendering(for: mediumMarkdown))
        XCTAssertNil(MarkdownPreviewView.reloadDebounceDelay(for: mediumMarkdown))
        XCTAssertTrue(MarkdownPreviewView.usesBackgroundRendering(for: markdown))
        XCTAssertEqual(MarkdownPreviewView.reloadDebounceDelay(for: markdown), 1.2)
        XCTAssertEqual(MarkdownPreviewView.reloadDebounceDelay(for: veryLargeMarkdown), 0.9)
        XCTAssertEqual(MarkdownPreviewView.reloadDebounceDelay(for: massiveMarkdown), 1.2)
        XCTAssertFalse(MarkdownPreviewView.usesBackgroundRendering(for: "# Small\n\nBody"))
        XCTAssertFalse(MarkdownSyntaxHighlighter.usesFullHighlighting(characterCount: (markdown as NSString).length))
        XCTAssertNil(MarkdownPreviewView.reloadDebounceDelay(for: "# Small\n\nBody"))
        XCTAssertTrue(MarkdownSyntaxHighlighter.usesFullHighlighting(characterCount: 12_000))
        XCTAssertFalse(MarkdownPreviewView.enablesExternalRenderers(for: markdown))
        XCTAssertTrue(MarkdownPreviewView.enablesExternalRenderers(for: "# Small\n\n$E = mc^2$"))
        XCTAssertLessThan(
            (MarkdownPreviewView.markdownForPreviewRendering(markdown) as NSString).length,
            (markdown as NSString).length
        )
    }

    func testInitialPreviewLoadUsesShortGracePeriodForExternalOpenEvents() {
        XCTAssertEqual(
            MarkdownPreviewView.initialPreviewDebounceDelay(
                contentRevision: 0,
                baseURL: nil,
                lastHTML: nil
            ),
            MarkdownPreviewView.initialPreviewReloadDelay
        )
        XCTAssertNil(
            MarkdownPreviewView.initialPreviewDebounceDelay(
                contentRevision: 1,
                baseURL: nil,
                lastHTML: nil
            )
        )
        XCTAssertNil(
            MarkdownPreviewView.initialPreviewDebounceDelay(
                contentRevision: 0,
                baseURL: URL(fileURLWithPath: "/tmp"),
                lastHTML: nil
            )
        )
        XCTAssertNil(
            MarkdownPreviewView.initialPreviewDebounceDelay(
                contentRevision: 0,
                baseURL: nil,
                lastHTML: ""
            )
        )
    }

    func testMassivePreviewRenderingUsesTrimmedMarkdownCopy() {
        let smallMarkdown = "# Title\n\nBody"
        XCTAssertEqual(MarkdownPreviewView.markdownForPreviewRendering(smallMarkdown), smallMarkdown)

        let markdown = Self.largeMarkdown(paragraphCount: 15_000)
        let previewMarkdown = MarkdownPreviewView.markdownForPreviewRendering(markdown)

        XCTAssertLessThan((previewMarkdown as NSString).length, (markdown as NSString).length)
        XCTAssertLessThanOrEqual(
            (previewMarkdown as NSString).length,
            MarkdownPreviewView.massivePreviewRenderedCharacterLimit + 220
        )
        XCTAssertTrue(previewMarkdown.contains("超大文档预览已自动精简"))
        XCTAssertTrue(previewMarkdown.contains("完整"))
    }

    func testMassivePreviewRenderingClosesTrimmedCodeFence() {
        let markdown = String(repeating: "Intro paragraph alpha beta gamma.\n", count: 1_000) +
            "\n```swift\n" +
            String(repeating: "print(\"hello\")\n", count: 80_000)

        let previewMarkdown = MarkdownPreviewView.markdownForPreviewRendering(markdown)
        let fenceCount = previewMarkdown.components(separatedBy: "```").count - 1

        XCTAssertTrue(previewMarkdown.contains("超大文档预览已自动精简"))
        XCTAssertEqual(fenceCount % 2, 0)
    }

    func testPreviewScrollSyncInstallRetryDelayStopsAtLimit() {
        XCTAssertEqual(MarkdownPreviewView.scrollSyncInstallRetryDelay(forAttempt: 0) ?? 0, 0.15, accuracy: 0.001)
        XCTAssertEqual(MarkdownPreviewView.scrollSyncInstallRetryDelay(forAttempt: 1) ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(MarkdownPreviewView.scrollSyncInstallRetryDelay(forAttempt: 2) ?? 0, 0.45, accuracy: 0.001)
        XCTAssertNil(MarkdownPreviewView.scrollSyncInstallRetryDelay(forAttempt: 3))
    }

    func testPreviewScrollTargetUsesCachedSyncPathBeforeDomScanFallback() throws {
        let script = MarkdownPreviewView.scrollTargetScript(
            for: SourceLineScrollTarget(line: 42, revision: 7, anchorID: "heading-42")
        )

        let cachedPath = "window.moyeScrollSync.scrollToSourceLine(requestedLine, requestedAnchor)"
        let fallbackPath = "document.querySelectorAll('[data-source-line]')"

        XCTAssertTrue(script.contains(cachedPath))
        XCTAssertTrue(script.contains(fallbackPath))
        XCTAssertTrue(script.contains("sourceLineElementID"))
        XCTAssertTrue(script.contains("moye-source-line-${Math.max"))
        XCTAssertLessThan(
            try XCTUnwrap(script.range(of: cachedPath)?.lowerBound),
            try XCTUnwrap(script.range(of: fallbackPath)?.lowerBound)
        )
        XCTAssertTrue(script.contains(#""heading-42""#))
    }

    func testMainMenuLocalizerNormalizesSystemViewTitleVariants() {
        XCTAssertEqual(MainMenuLocalizer.localizedTitle("View", language: .chinese), "显示")
        XCTAssertEqual(MainMenuLocalizer.localizedTitle("视图", language: .chinese), "显示")
        XCTAssertEqual(MainMenuLocalizer.localizedTitle("显示", language: .chinese), "显示")
        XCTAssertEqual(MainMenuLocalizer.localizedTitle("视图", language: .english), "View")
        XCTAssertEqual(MainMenuLocalizer.localizedTitle("Help", language: .chinese), "帮助")
    }

    func testLargeDocumentEstimatedEditorHeightStaysStableAcrossScrollUpdates() {
        let markdown = Self.largeMarkdown(paragraphCount: 15_000)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 540))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 540))
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = markdown
        scrollView.documentView = textView

        MarkdownEditorView.updateTextContainerGeometry(
            for: scrollView,
            textView: textView,
            recalculateHeight: true
        )

        let estimatedHeight = textView.frame.height
        XCTAssertGreaterThan(estimatedHeight, scrollView.contentSize.height)

        let bottomY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        MarkdownEditorView.updateTextContainerGeometry(
            for: scrollView,
            textView: textView,
            recalculateHeight: false
        )

        XCTAssertEqual(textView.frame.height, estimatedHeight, accuracy: 0.5)
        XCTAssertLessThanOrEqual(scrollView.contentView.bounds.maxY, textView.frame.height + 1)
    }

    func testRendererPlainInlineFastPathOnlyAcceptsPlainText() {
        XCTAssertTrue(MarkdownRenderer.canRenderInlineAsPlainText("Paragraph alpha beta gamma."))
        XCTAssertTrue(MarkdownRenderer.canRenderInlineAsPlainText("中文段落没有 Markdown 标记。"))
        XCTAssertFalse(MarkdownRenderer.canRenderInlineAsPlainText("Use **bold** here."))
        XCTAssertFalse(MarkdownRenderer.canRenderInlineAsPlainText("Visit https://example.com"))
        XCTAssertFalse(MarkdownRenderer.canRenderInlineAsPlainText("Visit www.example.com"))
        XCTAssertFalse(MarkdownRenderer.canRenderInlineAsPlainText("5 < 7"))
    }

    func testRendererAddsLazyLayoutStylesForLargePreviewScrolling() {
        let html = MarkdownRenderer.renderDocument("# Title\n\nBody", enableExternalRenderers: false)

        XCTAssertTrue(html.contains("@supports (content-visibility: auto)"))
        XCTAssertTrue(html.contains("content-visibility: auto;"))
        XCTAssertTrue(html.contains("contain-intrinsic-size: auto 48px;"))
    }

    func testRendererSupportsLocalImagePathsWithSpaces() {
        let imagePath = "/Users/anthony/Desktop/Snipaste 2026-06-20 01-31-00.png"
        let expectedURL = URL(fileURLWithPath: imagePath).absoluteString
        let html = MarkdownRenderer.renderDocument(
            "![shot](\(imagePath))",
            enableExternalRenderers: false
        )

        XCTAssertTrue(html.contains(#"<img src="\#(expectedURL)" alt="shot">"#))
        XCTAssertFalse(html.contains("Snipaste<em>"))
    }

    func testRendererDoesNotAutolinkInsideImageDataURI() {
        let dataURI = "data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%3E%3C/svg%3E"
        let html = MarkdownRenderer.renderDocument(
            "![logo](\(dataURI))",
            enableExternalRenderers: false
        )
        let escapedDataURI = dataURI.replacingOccurrences(of: "'", with: "&#39;")

        XCTAssertTrue(html.contains(#"<img src="\#(escapedDataURI)" alt="logo">"#))
        XCTAssertFalse(html.contains(#"<a href="http://www.w3.org/2000/svg""#))
    }

    func testRendererDoesNotEmphasizeUnderscoresInsideImageHTML() {
        let html = MarkdownRenderer.renderDocument(
            "![Snipaste_2026-06-20_01-31-00](assets/Snipaste_2026-06-20_01-31-00.png)",
            enableExternalRenderers: false
        )

        XCTAssertTrue(html.contains(#"<img src="assets/Snipaste_2026-06-20_01-31-00.png" alt="Snipaste_2026-06-20_01-31-00">"#))
        XCTAssertFalse(html.contains("Snipaste<em>"))
        XCTAssertFalse(html.contains(#"src="assets/Snipaste<em>"#))
    }

    func testRendererEmitsSourceLineAnchorsForBlockScrollSync() {
        let markdown = """
        # Title

        Paragraph text.

        | A | B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        print("hello")
        ```
        """
        let html = MarkdownRenderer.renderDocument(markdown, enableExternalRenderers: false)

        XCTAssertTrue(html.contains(#"<h1 data-source-line="1" id="title">Title</h1>"#))
        XCTAssertTrue(html.contains(#"<p data-source-line="3" id="moye-source-line-3">Paragraph text.</p>"#))
        XCTAssertTrue(html.contains(#"<table data-source-line="5" id="moye-source-line-5">"#))
        XCTAssertTrue(html.contains(#"<figure class="code-block" data-source-line="9" id="moye-source-line-9">"#))
    }

    func testRendererPreservesListBoundariesWhenSwitchingListTypes() {
        let markdown = """
        1. Ordered
        - Unordered
        2. Ordered again
        """
        let html = MarkdownRenderer.renderDocument(markdown, enableExternalRenderers: false)

        XCTAssertTrue(html.contains("</ol>\n<ul"))
        XCTAssertTrue(html.contains("</ul>\n<ol"))
        XCTAssertTrue(html.contains(#"<ol data-source-line="1">"#))
        XCTAssertTrue(html.contains(#"<ul data-source-line="2">"#))
        XCTAssertFalse(html.contains(#"<ol data-source-line="1" id="moye-source-line-1">"#))
        XCTAssertFalse(html.contains(#"<ul data-source-line="2" id="moye-source-line-2">"#))
        XCTAssertTrue(html.contains(#"<li data-source-line="1" id="moye-source-line-1">Ordered</li>"#))
        XCTAssertTrue(html.contains(#"<li data-source-line="2" id="moye-source-line-2">Unordered</li>"#))
        XCTAssertTrue(html.contains(#"<li data-source-line="3" id="moye-source-line-3">Ordered again</li>"#))
    }

    func testOutlineJumpPublishesSourceLineNavigationTarget() {
        let store = DocumentStore()
        store.markdown = """
        # Top

        Intro
        ## Details
        Body
        """

        let item = store.outline[1]
        let expectedLocation = (store.markdown as NSString).range(of: "## Details").location
        store.jumpToOutlineItem(item)

        XCTAssertEqual(item.title, "Details")
        XCTAssertEqual(item.line, 4)
        XCTAssertEqual(store.selectedRange.location, expectedLocation)
        XCTAssertEqual(store.editorNavigationTarget?.line, 4)
        XCTAssertEqual(store.editorNavigationTarget?.revision, 1)
        XCTAssertEqual(store.editorNavigationTarget?.location, expectedLocation)
        XCTAssertEqual(store.editorNavigationTarget?.anchorID, "details")

        store.jumpToOutlineItem(item)

        XCTAssertEqual(store.editorNavigationTarget?.line, 4)
        XCTAssertEqual(store.editorNavigationTarget?.revision, 2)
        XCTAssertEqual(store.editorNavigationTarget?.location, expectedLocation)
        XCTAssertEqual(store.editorNavigationTarget?.anchorID, "details")
    }

    func testPreviewHTMLInjectsBaseTagForRelativeLocalImages() {
        let baseURL = URL(fileURLWithPath: "/Users/anthony/Documents/notes", isDirectory: true)
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
        </head>
        <body><img src="assets/a.png"></body>
        </html>
        """

        let previewHTML = MarkdownPreviewFileAccess.htmlWithBaseTag(html, baseURL: baseURL)

        XCTAssertTrue(previewHTML.contains(#"<base href="file:///Users/anthony/Documents/notes/">"#))
    }

    func testPreviewReadAccessIncludesLocalImageDirectory() {
        let baseURL = URL(fileURLWithPath: "/Users/anthony/Documents/notes", isDirectory: true)
        let htmlFileURL = URL(
            fileURLWithPath: "/Users/anthony/Library/Caches/MoyePreview/preview.html"
        )
        let markdown = """
        ![relative](assets/local.png)
        ![absolute](/Users/anthony/Desktop/Snipaste 2026-06-20 01-31-00.png)
        """

        let localURLs = MarkdownPreviewFileAccess.localImageFileURLs(in: markdown, baseURL: baseURL)
        let readAccessURL = MarkdownPreviewFileAccess.readAccessURL(
            baseURL: baseURL,
            markdown: markdown,
            htmlFileURL: htmlFileURL
        )

        XCTAssertTrue(localURLs.contains {
            $0.path == "/Users/anthony/Documents/notes/assets/local.png"
        })
        XCTAssertTrue(localURLs.contains {
            $0.path == "/Users/anthony/Desktop/Snipaste 2026-06-20 01-31-00.png"
        })
        XCTAssertEqual(readAccessURL.path, "/Users/anthony")
    }

    func testPreviewWebViewLoadsLocalImageFile() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let imageURL = folderURL.appendingPathComponent("pixel image.png")
        let imageData = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/axJ2k0AAAAASUVORK5CYII="))
        try imageData.write(to: imageURL)

        let markdown = "![pixel](\(imageURL.path))"
        let html = MarkdownRenderer.renderDocument(markdown, enableExternalRenderers: false)
        let previewHTML = MarkdownPreviewFileAccess.htmlWithBaseTag(html, baseURL: folderURL)
        let htmlFileURL = folderURL.appendingPathComponent("preview.html")
        try previewHTML.write(to: htmlFileURL, atomically: true, encoding: .utf8)

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let observer = WebViewLoadObserver()
        let readAccessURL = MarkdownPreviewFileAccess.readAccessURL(
            baseURL: folderURL,
            markdown: markdown,
            htmlFileURL: htmlFileURL
        )

        try await observer.load(webView, fileURL: htmlFileURL, readAccessURL: readAccessURL)
        let naturalWidth = try await webView.evaluateNumberJavaScript("document.images[0]?.naturalWidth || 0")

        XCTAssertEqual(naturalWidth, 1)
    }

    func testWorkspaceSearchMatchesFileContent() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let fileURL = folderURL.appendingPathComponent("notes.md")
        try "# Notes\n\nFind this needle in body text.\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspaceURL = folderURL
        store.fileSearchQuery = "needle"

        XCTAssertEqual(store.workspaceSearchResults.count, 1)
        XCTAssertEqual(store.workspaceSearchResults.first?.matchKind, .content)
        XCTAssertEqual(store.workspaceSearchResults.first?.file.displayName, "notes.md")
        XCTAssertTrue(store.workspaceSearchResults.first?.snippet?.contains("needle") == true)

        store.fileSearchQuery = "NEEDLE"

        XCTAssertEqual(store.workspaceSearchResults.count, 1)
        XCTAssertEqual(store.workspaceSearchResults.first?.matchKind, .content)
    }

    func testWorkspaceSearchResultsRefreshOnlyWhenQueryOrFilesChange() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let firstURL = folderURL.appendingPathComponent("first.md")
        let secondURL = folderURL.appendingPathComponent("second.md")
        try "alpha body\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "beta body\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspaceURL = folderURL
        store.fileSearchQuery = "alpha"

        XCTAssertEqual(store.workspaceSearchResults.map(\.file.displayName), ["first.md"])

        store.fileSearchQuery = "beta"

        XCTAssertEqual(store.workspaceSearchResults.map(\.file.displayName), ["second.md"])

        let thirdURL = folderURL.appendingPathComponent("third.md")
        try "beta launch note\n".write(to: thirdURL, atomically: true, encoding: .utf8)
        store.workspaceURL = nil
        store.workspaceURL = folderURL

        XCTAssertEqual(Set(store.workspaceSearchResults.map(\.file.displayName)), ["second.md", "third.md"])
    }

    func testWorkspaceSearchSkipsOversizedFileContent() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let largeFileURL = folderURL.appendingPathComponent("large.md")
        let oversizedText = String(repeating: "padding line without match\n", count: 95_000) +
            "\nlarge-only-search-token\n"
        try oversizedText.write(to: largeFileURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspaceURL = folderURL
        store.fileSearchQuery = "large-only-search-token"

        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: largeFileURL.path)[.size] as? NSNumber)?.intValue ?? 0, 2_000_000)
        XCTAssertTrue(store.workspaceSearchResults.isEmpty)
    }

    func testWorkspaceListingIncludesDirectoriesAndFiles() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = folderURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let markdownURL = nestedURL.appendingPathComponent("guide.md")
        let imageURL = nestedURL.appendingPathComponent("diagram.png")
        try "# Guide\n".write(to: markdownURL, atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: imageURL)

        let store = DocumentStore()
        store.workspaceURL = folderURL

        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "docs" && $0.isDirectory })
        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "docs/guide.md" && $0.isTextLike })
        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "docs/diagram.png" && !$0.isTextLike })
    }

    func testOpenDocumentAtURLLoadsFileAndWorkspaceFolder() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let fileURL = folderURL.appendingPathComponent("notes.md")
        try "# Notes\n\nOpened from URL.\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()

        XCTAssertTrue(store.openDocument(at: fileURL))
        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertEqual(store.workspaceURL, folderURL)
        XCTAssertEqual(store.markdown, "# Notes\n\nOpened from URL.\n")
        XCTAssertFalse(store.isDirty)
    }

    func testDocumentStoreInitialDocumentURLLoadsBeforeFirstViewRender() throws {
        let fileURL = try Self.writeTemporaryMarkdown("# Startup\n\nOpened before the first view render.\n")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore(initialDocumentURL: fileURL)

        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertEqual(store.workspaceURL, fileURL.deletingLastPathComponent())
        XCTAssertEqual(store.markdown, "# Startup\n\nOpened before the first view render.\n")
        XCTAssertFalse(store.isDirty)
    }

    func testAppLaunchURLResolverUsesFirstExistingFileArgument() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let firstURL = folderURL.appendingPathComponent("first.md")
        let secondURL = folderURL.appendingPathComponent("second.md")
        try "# First\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# Second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let resolvedURL = AppLaunchURLResolver.firstOpenableFileURL(
            arguments: [
                "/Applications/Moye.app/Contents/MacOS/Moye",
                "-psn_0_12345",
                folderURL.appendingPathComponent("missing.md").path,
                secondURL.absoluteString,
                firstURL.path,
            ]
        )

        XCTAssertEqual(resolvedURL?.path, secondURL.standardizedFileURL.path)
    }

    func testOpenDocumentAtURLLoadsLargeMarkdownForExternalOpenEvents() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let fileURL = folderURL.appendingPathComponent("large-150k.md")
        let markdown = Self.largeMarkdown(paragraphCount: 15_000)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()

        XCTAssertTrue(store.openDocument(at: fileURL))
        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertEqual(store.workspaceURL, folderURL)
        XCTAssertEqual(store.markdown.utf16.count, markdown.utf16.count)
        XCTAssertEqual(store.wordCount, MarkdownBlockIndex(markdown: markdown).statistics.wordCount)
        XCTAssertFalse(store.isDirty)
    }

    func testLargeDocumentDelayedDerivedDataRefreshKeepsIncrementalBlockReuse() throws {
        let markdown = Self.largeMarkdown(paragraphCount: 2_500)
        let fileURL = try Self.writeTemporaryMarkdown(markdown, fileName: "large.md")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))
        let retainedBlockID = try XCTUnwrap(store.blockIndex.blocks.last?.id)
        let editedMarkdown = markdown.replacingOccurrences(
            of: "Paragraph 1777 alpha beta gamma",
            with: "Paragraph 1777 alpha beta gamma edited words"
        )

        store.markdown = editedMarkdown
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))

        XCTAssertEqual(store.blockIndex.statistics, MarkdownBlockIndex(markdown: editedMarkdown).statistics)
        XCTAssertEqual(store.blockIndex.blocks.last?.id, retainedBlockID)
    }

    func testOpenDocumentAtURLAcceptsFolderAsWorkspace() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        try "# Guide\n".write(
            to: folderURL.appendingPathComponent("guide.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = DocumentStore()

        XCTAssertTrue(store.openDocument(at: folderURL))
        XCTAssertEqual(store.workspaceURL, folderURL)
        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "guide.md" })
    }

    func testWorkspaceTreeBuildsNestedDirectoriesAndVisibleRows() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docsURL = folderURL.appendingPathComponent("docs", isDirectory: true)
        let apiURL = docsURL.appendingPathComponent("api", isDirectory: true)
        try FileManager.default.createDirectory(at: apiURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        try "# Guide\n".write(
            to: docsURL.appendingPathComponent("guide.md"),
            atomically: true,
            encoding: .utf8
        )
        try "GET /health\n".write(
            to: apiURL.appendingPathComponent("routes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let store = DocumentStore()
        store.workspaceURL = folderURL

        let docsNode = try XCTUnwrap(store.workspaceTree.first { $0.file.relativePath == "docs" })
        XCTAssertTrue(docsNode.file.isDirectory)
        XCTAssertTrue(docsNode.children.contains { $0.file.relativePath == "docs/api" })
        XCTAssertTrue(docsNode.children.contains { $0.file.relativePath == "docs/guide.md" })

        store.toggleWorkspaceDirectory(docsNode.file)

        XCTAssertTrue(store.visibleWorkspaceTreeRows.contains { row in
            row.file.relativePath == "docs/guide.md" && row.depth == 1
        })
        XCTAssertTrue(store.visibleWorkspaceTreeRows.contains { row in
            row.file.relativePath == "docs/api" && row.depth == 1
        })
    }

    func testQuickOpenMatchesTextFileContent() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let noteURL = folderURL.appendingPathComponent("release.md")
        let imageURL = folderURL.appendingPathComponent("diagram.png")
        try "The launch codename is lotus.\n".write(to: noteURL, atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: imageURL)

        let store = DocumentStore()
        store.workspaceURL = folderURL
        store.quickOpenQuery = "lotus"

        XCTAssertEqual(store.quickOpenResults.count, 1)
        XCTAssertEqual(store.quickOpenResults.first?.matchKind, .content)
        XCTAssertEqual(store.quickOpenResults.first?.file.relativePath, "release.md")
        XCTAssertFalse(store.quickOpenResults.contains { $0.file.relativePath == "diagram.png" })
    }

    func testWorkspaceFileCreationDefaultsToMarkdownAndOpensFile() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let store = DocumentStore()
        store.workspaceURL = folderURL

        let createdURL = try XCTUnwrap(store.createWorkspaceFile(named: "draft", in: nil))

        XCTAssertEqual(createdURL.lastPathComponent, "draft.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(store.fileURL, createdURL)
        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "draft.md" && $0.isTextLike })
    }

    func testWorkspaceFolderCreationAndNestedFileCreation() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let store = DocumentStore()
        store.workspaceURL = folderURL

        let docsURL = try XCTUnwrap(store.createWorkspaceFolder(named: "docs", in: nil))
        let docsFile = try XCTUnwrap(store.workspaceFiles.first {
            $0.url.standardizedFileURL.path == docsURL.standardizedFileURL.path
        })
        let guideURL = try XCTUnwrap(store.createWorkspaceFile(
            named: "guide.md",
            in: docsFile,
            openCreatedFile: false
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: docsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guideURL.path))
        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "docs/guide.md" })
    }

    func testWorkspaceRenameUpdatesOpenFileURL() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let store = DocumentStore()
        store.workspaceURL = folderURL
        let createdURL = try XCTUnwrap(store.createWorkspaceFile(named: "old.md", in: nil))
        let file = try XCTUnwrap(store.workspaceFiles.first {
            $0.url.standardizedFileURL.path == createdURL.standardizedFileURL.path
        })

        let renamedURL = try XCTUnwrap(store.renameWorkspaceItem(file, to: "new.md"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(
            store.fileURL?.resolvingSymlinksInPath().path,
            renamedURL.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(store.workspaceFiles.contains { $0.relativePath == "new.md" })
    }

    func testUndoRedoTracksMarkdownChanges() {
        let store = DocumentStore()
        store.markdown = "first"
        store.markdown = "second"

        XCTAssertTrue(store.canUndo)
        store.undoEditing()
        XCTAssertEqual(store.markdown, "first")

        XCTAssertTrue(store.canRedo)
        store.redoEditing()
        XCTAssertEqual(store.markdown, "second")
    }

    func testDocumentStoreAppliesEditorTextEditThroughTextBuffer() throws {
        let fileURL = try Self.writeTemporaryMarkdown("alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))

        let range = (store.markdown as NSString).range(of: "beta")
        store.applyEditorTextEdit(
            SourceLineIndexEdit(range: range, replacement: "b1\nb2"),
            selectedRangeAfter: NSRange(location: range.location + ("b1\nb2" as NSString).length, length: 0),
            completeTextFallback: { "alpha\nb1\nb2" }
        )

        XCTAssertEqual(store.markdown, "alpha\nb1\nb2")
        XCTAssertEqual(store.lineCount, 3)
        XCTAssertTrue(store.isDirty)

        store.undoEditing()

        XCTAssertEqual(store.markdown, "alpha\nbeta")
        XCTAssertFalse(store.isDirty)

        store.redoEditing()

        XCTAssertEqual(store.markdown, "alpha\nb1\nb2")
        XCTAssertTrue(store.isDirty)
    }

    func testDocumentStoreDoesNotReadCompleteTextFallbackForValidEditorEdit() throws {
        let fileURL = try Self.writeTemporaryMarkdown("alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))

        var fallbackReadCount = 0
        let range = (store.markdown as NSString).range(of: "beta")
        store.applyEditorTextEdit(
            SourceLineIndexEdit(range: range, replacement: "gamma"),
            selectedRangeAfter: NSRange(location: range.location + ("gamma" as NSString).length, length: 0),
            completeTextFallback: {
                fallbackReadCount += 1
                return "alpha\ngamma"
            }
        )

        XCTAssertEqual(store.markdown, "alpha\ngamma")
        XCTAssertEqual(fallbackReadCount, 0)
    }

    func testUndoCanReturnSmallDocumentToCleanSavedState() {
        let store = DocumentStore()
        let savedMarkdown = store.markdown

        store.markdown = "changed"

        XCTAssertTrue(store.isDirty)

        store.undoEditing()

        XCTAssertEqual(store.markdown, savedMarkdown)
        XCTAssertFalse(store.isDirty)
    }

    func testUndoCoalescesAdjacentTypedInsertionsIntoSingleStep() throws {
        let fileURL = try Self.writeTemporaryMarkdown("alpha")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))

        for character in ["H", "e", "l", "l", "o"] {
            let range = store.selectedRange
            store.markdown = (store.markdown as NSString).replacingCharacters(in: range, with: character)
            store.selectedRange = NSRange(location: range.location + 1, length: 0)
        }

        XCTAssertEqual(store.markdown, "Helloalpha")
        XCTAssertTrue(store.isDirty)

        store.undoEditing()

        XCTAssertEqual(store.markdown, "alpha")
        XCTAssertFalse(store.isDirty)

        store.redoEditing()

        XCTAssertEqual(store.markdown, "Helloalpha")
        XCTAssertTrue(store.isDirty)
    }

    func testUndoKeepsDisjointInsertionsAsSeparateSteps() throws {
        let fileURL = try Self.writeTemporaryMarkdown("alpha")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))

        store.markdown = "Aalpha"
        store.selectedRange = NSRange(location: (store.markdown as NSString).length, length: 0)
        store.markdown = "AalphaZ"

        store.undoEditing()

        XCTAssertEqual(store.markdown, "Aalpha")
        XCTAssertTrue(store.isDirty)
    }

    func testUndoCoalescesAdjacentBackspaceDeletesIntoSingleStep() throws {
        let fileURL = try Self.writeTemporaryMarkdown("abcdef")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))
        store.selectedRange = NSRange(location: 6, length: 0)

        store.markdown = "abcde"
        store.selectedRange = NSRange(location: 5, length: 0)
        store.markdown = "abcd"
        store.selectedRange = NSRange(location: 4, length: 0)

        XCTAssertEqual(store.markdown, "abcd")
        XCTAssertTrue(store.isDirty)

        store.undoEditing()

        XCTAssertEqual(store.markdown, "abcdef")
        XCTAssertFalse(store.isDirty)
    }

    func testLargeDocumentDirtyStateTracksSaveWithoutRepeatedFullComparisons() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let store = DocumentStore()
        store.workspaceURL = folderURL
        let fileURL = try XCTUnwrap(store.createWorkspaceFile(named: "large.md", in: nil))
        let markdown = Self.largeMarkdown(paragraphCount: 2_500)

        XCTAssertFalse(store.isDirty)

        store.markdown = markdown

        XCTAssertTrue(store.isDirty)

        let editedRevision = store.documentRevision
        store.saveDocument()

        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(store.documentRevision, editedRevision)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), markdown)

        store.markdown = markdown + "\n\nfinal note"

        XCTAssertTrue(store.isDirty)
    }

    func testUndoCanReturnLargeDocumentToCleanSavedState() throws {
        let markdown = Self.largeMarkdown(paragraphCount: 2_500)
        let fileURL = try Self.writeTemporaryMarkdown(markdown, fileName: "large.md")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(at: fileURL))
        XCTAssertFalse(store.isDirty)

        store.selectedRange = NSRange(location: 0, length: 0)
        store.markdown = "temporary note\n\n" + markdown

        XCTAssertTrue(store.isDirty)

        store.undoEditing()

        XCTAssertEqual(store.markdown.utf16.count, markdown.utf16.count)
        XCTAssertFalse(store.isDirty)
    }

    func testUndoRedoTracksLocalizedEditsInLargeMarkdown() {
        let store = DocumentStore()
        let base = (1...10_000)
            .map { "Line \($0) alpha beta gamma" }
            .joined(separator: "\n")
        let edited = base.replacingOccurrences(of: "Line 5000 alpha", with: "Line 5000 edited alpha")

        store.markdown = base
        store.selectedRange = NSRange(location: (base as NSString).range(of: "Line 5000").location, length: 0)
        store.markdown = edited

        store.undoEditing()
        XCTAssertEqual(store.markdown, base)

        store.redoEditing()
        XCTAssertEqual(store.markdown, edited)
    }

    func testTableRowAndColumnEditingUsesCurrentTable() {
        let store = DocumentStore()
        store.markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        store.selectedRange = NSRange(location: (store.markdown as NSString).range(of: "1").location, length: 0)

        store.insertTableRowBelow()
        XCTAssertTrue(store.markdown.contains("| 1 | 2 |\n|  |  |"))

        store.selectedRange = NSRange(location: (store.markdown as NSString).range(of: "1").location, length: 0)
        store.insertTableColumnRight()
        XCTAssertTrue(store.markdown.contains("| A |  | B |"))
        XCTAssertTrue(store.markdown.contains("| 1 |  | 2 |"))

        store.selectedRange = NSRange(location: (store.markdown as NSString).range(of: "1").location, length: 0)
        store.deleteCurrentTableColumn()
        XCTAssertTrue(store.markdown.contains("|  | B |"))
        XCTAssertTrue(store.markdown.contains("|  | 2 |"))
    }

    func testReleaseVersionComparatorHandlesGitHubTags() {
        XCTAssertTrue(ReleaseVersionComparator.isNewer("v0.2.0", than: "0.1.9"))
        XCTAssertTrue(ReleaseVersionComparator.isNewer("0.10.0", than: "0.2.0"))
        XCTAssertFalse(ReleaseVersionComparator.isNewer("v0.1.0", than: "0.1.0"))
        XCTAssertFalse(ReleaseVersionComparator.isNewer("0.1.0-beta.1", than: "0.1.0"))
    }

    func testPreviewReloadDecisionUsesContentRevisionInsteadOfFullMarkdownComparison() {
        let baseURL = URL(fileURLWithPath: "/tmp/moye")

        XCTAssertFalse(MarkdownPreviewView.shouldReloadPreview(
            contentRevision: 8,
            baseURL: baseURL,
            theme: .system,
            lastContentRevision: 8,
            lastBaseURL: baseURL,
            lastTheme: .system,
            lastHTML: "<html></html>"
        ))

        XCTAssertTrue(MarkdownPreviewView.shouldReloadPreview(
            contentRevision: 9,
            baseURL: baseURL,
            theme: .system,
            lastContentRevision: 8,
            lastBaseURL: baseURL,
            lastTheme: .system,
            lastHTML: "<html></html>"
        ))

        XCTAssertTrue(MarkdownPreviewView.shouldReloadPreview(
            contentRevision: 8,
            baseURL: baseURL,
            theme: .dark,
            lastContentRevision: 8,
            lastBaseURL: baseURL,
            lastTheme: .system,
            lastHTML: "<html></html>"
        ))
    }

    func testPreviewReuseSkipsReloadOnlyWhenRenderedPageIsEquivalent() {
        let baseURL = URL(fileURLWithPath: "/tmp/moye")

        XCTAssertTrue(MarkdownPreviewView.shouldReuseLoadedPreview(
            html: "<html><body>Hello</body></html>",
            baseURL: baseURL,
            theme: .system,
            lastHTML: "<html><body>Hello</body></html>",
            lastBaseURL: baseURL,
            lastTheme: .system,
            isPageLoaded: true
        ))

        XCTAssertFalse(MarkdownPreviewView.shouldReuseLoadedPreview(
            html: "<html><body>Hello</body></html>",
            baseURL: baseURL,
            theme: .system,
            lastHTML: "<html><body>Hello</body></html>",
            lastBaseURL: baseURL,
            lastTheme: .system,
            isPageLoaded: false
        ))

        XCTAssertFalse(MarkdownPreviewView.shouldReuseLoadedPreview(
            html: "<html><body>Hello</body></html>",
            baseURL: baseURL.appendingPathComponent("assets"),
            theme: .system,
            lastHTML: "<html><body>Hello</body></html>",
            lastBaseURL: baseURL,
            lastTheme: .system,
            isPageLoaded: true
        ))

        XCTAssertFalse(MarkdownPreviewView.shouldReuseLoadedPreview(
            html: "<html><body>Hello</body></html>",
            baseURL: baseURL,
            theme: .dark,
            lastHTML: "<html><body>Hello</body></html>",
            lastBaseURL: baseURL,
            lastTheme: .system,
            isPageLoaded: true
        ))
    }

    func testPreviewRenderCacheReusesOnlyEquivalentMarkdownAndTheme() {
        let cache = MarkdownPreviewRenderCache.shared
        cache.reset()
        cache.store(html: "<p>Hello</p>", for: "Hello", theme: .system)
        cache.store(html: "<p>Hello changed</p>", for: "Hello changed", theme: .system)
        defer { cache.reset() }

        XCTAssertEqual(cache.html(for: "Hello", theme: .system), "<p>Hello</p>")
        XCTAssertEqual(cache.html(for: "Hello changed", theme: .system), "<p>Hello changed</p>")
        XCTAssertNil(cache.html(for: "Hello", theme: .dark))
        XCTAssertNil(cache.html(for: "Hello again", theme: .system))
    }

    func testPreviewRenderCacheUsesLightweightKeyWithoutRetainingMarkdownBody() {
        let cache = MarkdownPreviewRenderCache.shared
        let largeMarkdown = Self.largeMarkdown(paragraphCount: 2_500)
        cache.reset()
        defer { cache.reset() }

        cache.store(html: "<html>large preview</html>", for: largeMarkdown, theme: .system)

        XCTAssertEqual(cache.html(for: largeMarkdown, theme: .system), "<html>large preview</html>")
        XCTAssertNil(cache.html(for: largeMarkdown + "\n\nchanged", theme: .system))
        XCTAssertEqual(cache.retainedMarkdownCharacterCountForTesting, 0)
    }

    func testPreviewRenderCacheKeyChangesForAppendedLargeMarkdown() {
        let markdown = Self.largeMarkdown(paragraphCount: 2_500)

        XCTAssertNotEqual(
            MarkdownPreviewRenderCache.Key(markdown: markdown, theme: .system),
            MarkdownPreviewRenderCache.Key(markdown: markdown + "\n\nnote", theme: .system)
        )
    }

    private static func writeTemporaryMarkdown(_ markdown: String, fileName: String = "note.md") throws -> URL {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent(fileName)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func largeMarkdown(paragraphCount: Int) -> String {
        (1...paragraphCount).map { index in
            var blocks: [String] = []
            if index % 75 == 1 {
                blocks.append("# Section \(index)")
            }
            blocks.append("Paragraph \(index) alpha beta gamma delta epsilon zeta eta theta iota kappa.")
            if index % 500 == 0 {
                blocks.append("""
                ```swift
                print("block \(index)")
                ```
                """)
            }
            if index % 900 == 0 {
                blocks.append("""
                | A | B | C |
                | --- | --- | --- |
                | \(index) | value | notes |
                """)
            }
            return blocks.joined(separator: "\n\n")
        }
        .joined(separator: "\n\n")
    }
}

private final class WebViewLoadObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ webView: WKWebView, fileURL: URL, readAccessURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private extension WKWebView {
    func evaluateNumberJavaScript(_ script: String) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let number = result as? NSNumber {
                    continuation.resume(returning: number.intValue)
                    return
                }

                continuation.resume(returning: 0)
            }
        }
    }
}
