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
        XCTAssertTrue(html.contains(#"<p data-source-line="3">Paragraph text.</p>"#))
        XCTAssertTrue(html.contains(#"<table data-source-line="5">"#))
        XCTAssertTrue(html.contains(#"<figure class="code-block" data-source-line="9">"#))
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
