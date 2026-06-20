import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    static let initialPreviewReloadDelay: TimeInterval = 0.25
    static let backgroundRenderCharacterLimit = 80_000
    static let externalRendererCharacterLimit = 500_000
    static let massivePreviewCharacterLimit = 1_000_000
    static let massivePreviewRenderedCharacterLimit = 300_000
    static let debouncedReloadCharacterLimit = 250_000
    static let veryLargeDebouncedReloadCharacterLimit = 500_000
    static let massiveDebouncedReloadCharacterLimit = 1_000_000
    static let scrollSyncInstallRetryLimit = 3

    let markdown: String
    let contentRevision: Int
    let baseURL: URL?
    let theme: PreviewTheme
    let scrollTarget: SourceLineScrollTarget?
    let onVisibleSourceLineChange: (Int) -> Void

    static func reloadDebounceDelay(for markdown: String) -> TimeInterval? {
        let characterCount = (markdown as NSString).length
        if characterCount > massiveDebouncedReloadCharacterLimit {
            return 1.2
        }
        if characterCount > veryLargeDebouncedReloadCharacterLimit {
            return 0.9
        }
        return characterCount > debouncedReloadCharacterLimit ? 0.65 : nil
    }

    static func initialPreviewDebounceDelay(
        contentRevision: Int,
        baseURL: URL?,
        lastHTML: String?
    ) -> TimeInterval? {
        guard contentRevision == 0, baseURL == nil, lastHTML == nil else {
            return nil
        }
        return initialPreviewReloadDelay
    }

    static func usesBackgroundRendering(for markdown: String) -> Bool {
        (markdown as NSString).length > backgroundRenderCharacterLimit
    }

    static func enablesExternalRenderers(for markdown: String) -> Bool {
        (markdown as NSString).length <= externalRendererCharacterLimit
    }

    static func markdownForPreviewRendering(_ markdown: String) -> String {
        let originalCharacterCount = (markdown as NSString).length
        guard originalCharacterCount > massivePreviewCharacterLimit else {
            return markdown
        }

        var previewMarkdown = String(markdown.prefix(massivePreviewRenderedCharacterLimit))
        if let lastNewline = previewMarkdown.lastIndex(of: "\n") {
            previewMarkdown = String(previewMarkdown[..<lastNewline])
        }
        if hasUnclosedCodeFence(in: previewMarkdown) {
            previewMarkdown.append("\n```")
        }

        let renderedCharacterCount = (previewMarkdown as NSString).length
        previewMarkdown.append(
            """


            ---

            > 超大文档预览已自动精简：当前渲染前 \(renderedCharacterCount) 个字符，完整 \(originalCharacterCount) 个字符仍在编辑器中，可继续搜索、编辑和保存。
            """
        )
        return previewMarkdown
    }

    private static func hasUnclosedCodeFence(in markdown: String) -> Bool {
        var isInCodeFence = false
        markdown.enumerateLines { line, _ in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInCodeFence.toggle()
            }
        }
        return isInCodeFence
    }

    static func scrollSyncInstallRetryDelay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt < scrollSyncInstallRetryLimit else {
            return nil
        }
        return min(0.15 * Double(attempt + 1), 0.6)
    }

    static func shouldReloadPreview(
        contentRevision: Int,
        baseURL: URL?,
        theme: PreviewTheme,
        lastContentRevision: Int?,
        lastBaseURL: URL?,
        lastTheme: PreviewTheme?,
        lastHTML: String?
    ) -> Bool {
        contentRevision != lastContentRevision ||
            baseURL != lastBaseURL ||
            theme != lastTheme ||
            lastHTML == nil
    }

    static func shouldReuseLoadedPreview(
        html: String,
        baseURL: URL?,
        theme: PreviewTheme,
        lastHTML: String?,
        lastBaseURL: URL?,
        lastTheme: PreviewTheme?,
        isPageLoaded: Bool
    ) -> Bool {
        isPageLoaded &&
            html == lastHTML &&
            baseURL == lastBaseURL &&
            theme == lastTheme
    }

    static func scrollTargetScript(for target: SourceLineScrollTarget) -> String {
        let line = max(1, target.line)
        let anchorLiteral = target.anchorID.map(javaScriptStringLiteral) ?? "null"
        return """
        (() => {
          const requestedLine = \(line);
          const requestedAnchor = \(anchorLiteral);
          const sourceLineElementID = (line) => `moye-source-line-${Math.max(1, Number.parseInt(line, 10) || 1)}`;

          if (window.moyeScrollSync && typeof window.moyeScrollSync.scrollToSourceLine === 'function') {
            return window.moyeScrollSync.scrollToSourceLine(requestedLine, requestedAnchor);
          }

          const anchorElement = requestedAnchor ? document.getElementById(requestedAnchor) : null;
          const exactSourceLineElement = document.getElementById(sourceLineElementID(requestedLine));

          const blocks = Array.from(document.querySelectorAll('[data-source-line]'))
            .map((element) => ({
              element,
              line: Number.parseInt(element.getAttribute('data-source-line') || '1', 10)
            }))
            .filter((block) => Number.isFinite(block.line) && block.line > 0)
            .sort((left, right) => left.line - right.line);

          if (!blocks.length && !anchorElement && !exactSourceLineElement) {
            return { ok: false, reason: 'no-source-line-blocks' };
          }

          const targetForLine = () => {
            if (!blocks.length) {
              return null;
            }

            let target = blocks[0];
            for (const block of blocks) {
              if (block.line <= requestedLine) {
                target = block;
                continue;
              }

              if (Math.abs(block.line - requestedLine) < Math.abs(target.line - requestedLine)) {
                target = block;
              }
              break;
            }
            return target;
          };

          const target = anchorElement
            ? { element: anchorElement, line: requestedLine }
            : exactSourceLineElement
              ? { element: exactSourceLineElement, line: requestedLine }
            : targetForLine();

          if (!target) {
            return { ok: false, reason: 'no-target' };
          }

          const scrollingElement = () => {
            return document.scrollingElement || document.documentElement || document.body;
          };
          const currentScrollTop = () => {
            const element = scrollingElement();
            return Math.max(
              element ? element.scrollTop || 0 : 0,
              window.pageYOffset || 0,
              window.scrollY || 0
            );
          };
          const scrollToY = (value) => {
            const top = Math.max(0, value);
            if (document.documentElement) {
              document.documentElement.scrollTop = top;
            }
            if (document.body) {
              document.body.scrollTop = top;
            }
            const element = scrollingElement();
            if (element) {
              element.scrollTop = top;
            }
            window.scrollTo({ top, left: window.scrollX || 0, behavior: 'auto' });
          };
          const jump = () => {
            target.element.scrollIntoView({ block: 'start', inline: 'nearest', behavior: 'auto' });
            scrollToY(currentScrollTop() - 16);
          };

          if (window.moyeScrollSync) {
            window.moyeScrollSync.programmatic = true;
          }
          jump();
          window.requestAnimationFrame(jump);
          window.setTimeout(() => {
            if (window.moyeScrollSync) {
              window.moyeScrollSync.programmatic = false;
            }
          }, 250);

          return { ok: true, requestedLine, matchedLine: target.line, cached: false, exact: !!exactSourceLineElement };
        })();
        """
    }

    static func javaScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
            .replacingOccurrences(of: "\n", with: #"\\n"#)
            .replacingOccurrences(of: "\r", with: #"\\r"#)
            .replacingOccurrences(of: "\u{2028}", with: #"\\u2028"#)
            .replacingOccurrences(of: "\u{2029}", with: #"\\u2029"#)
        return #""\#(escaped)""#
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibleSourceLineChange: onVisibleSourceLineChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onVisibleSourceLineChange = onVisibleSourceLineChange

        if Self.shouldReloadPreview(
            contentRevision: contentRevision,
            baseURL: baseURL,
            theme: theme,
            lastContentRevision: context.coordinator.lastContentRevision,
            lastBaseURL: context.coordinator.lastBaseURL,
            lastTheme: context.coordinator.lastTheme,
            lastHTML: context.coordinator.lastHTML
        ) {
            context.coordinator.schedulePreviewReload(
                markdown: markdown,
                contentRevision: contentRevision,
                baseURL: baseURL,
                theme: theme,
                scrollTarget: scrollTarget,
                debounceDelay: Self.reloadDebounceDelay(for: markdown) ??
                    Self.initialPreviewDebounceDelay(
                        contentRevision: contentRevision,
                        baseURL: baseURL,
                        lastHTML: context.coordinator.lastHTML
                    ),
                in: webView
            )
            return
        }

        if let scrollTarget {
            context.coordinator.applyScrollTarget(scrollTarget, in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelPendingPreviewReload()
        coordinator.tearDownNativeScrollObserver()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageName = "sourceLineScroll"

        var lastContentRevision: Int?
        var lastHTML: String?
        var lastBaseURL: URL?
        var lastTheme: PreviewTheme?
        var onVisibleSourceLineChange: (Int) -> Void
        var isPageLoaded = false
        var isScrollSyncInstalled = false
        var lastAppliedScrollTarget: SourceLineScrollTarget?
        var pendingScrollTarget: SourceLineScrollTarget?
        private var pendingScrollReapply: DispatchWorkItem?
        private var pendingPreviewReload: DispatchWorkItem?
        private var pendingScrollSyncInstallRetry: DispatchWorkItem?
        private var nativeScrollObserver: NSObjectProtocol?
        private var pendingNativeScrollPublish: DispatchWorkItem?
        private weak var observedScrollView: NSScrollView?
        private var isApplyingProgrammaticScroll = false
        private var lastVisibleSourceLine: Int?
        private var previewReloadRevision = 0
        private var previewReloadRequestID = 0
        private var scrollSyncInstallAttempt = 0
        private let previewFileName = "preview-\(UUID().uuidString).html"
        private static let previewRenderQueue = DispatchQueue(
            label: "org.moyesource.moye.preview-render",
            qos: .userInitiated
        )

        init(onVisibleSourceLineChange: @escaping (Int) -> Void) {
            self.onVisibleSourceLineChange = onVisibleSourceLineChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            scrollSyncInstallAttempt = 0
            installScrollSyncScript(in: webView)
            configureNativeScrollObserver(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageName, !isApplyingProgrammaticScroll else {
                return
            }

            let line: Int?
            if let number = message.body as? NSNumber {
                line = number.intValue
            } else if let string = message.body as? String {
                line = Int(string)
            } else {
                line = nil
            }

            guard let line, line > 0 else {
                return
            }

            publishSourceLine(line)
        }

        func cancelPendingPreviewReload() {
            pendingPreviewReload?.cancel()
            pendingPreviewReload = nil
            previewReloadRequestID += 1
        }

        func cancelPendingScrollSyncInstallRetry() {
            pendingScrollSyncInstallRetry?.cancel()
            pendingScrollSyncInstallRetry = nil
        }

        func tearDownNativeScrollObserver() {
            pendingNativeScrollPublish?.cancel()
            pendingNativeScrollPublish = nil
            cancelPendingScrollSyncInstallRetry()
            if let nativeScrollObserver {
                NotificationCenter.default.removeObserver(nativeScrollObserver)
            }
            nativeScrollObserver = nil
            observedScrollView = nil
        }

        func schedulePreviewReload(
            markdown: String,
            contentRevision: Int,
            baseURL: URL?,
            theme: PreviewTheme,
            scrollTarget: SourceLineScrollTarget?,
            debounceDelay: TimeInterval?,
            in webView: WKWebView
        ) {
            cancelPendingPreviewReload()
            previewReloadRequestID += 1
            let requestID = previewReloadRequestID
            lastContentRevision = contentRevision
            lastBaseURL = baseURL
            lastTheme = theme
            if lastHTML == nil {
                lastHTML = ""
            }

            let work = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else {
                    return
                }
                guard self.previewReloadRequestID == requestID else {
                    return
                }

                if MarkdownPreviewView.usesBackgroundRendering(for: markdown) {
                    self.renderPreviewInBackground(
                        markdown: markdown,
                        contentRevision: contentRevision,
                        baseURL: baseURL,
                        theme: theme,
                        scrollTarget: scrollTarget,
                        requestID: requestID,
                        in: webView
                    )
                } else {
                    self.reloadPreview(
                        markdown: markdown,
                        contentRevision: contentRevision,
                        baseURL: baseURL,
                        theme: theme,
                        scrollTarget: scrollTarget,
                        in: webView
                    )
                }
            }

            pendingPreviewReload = work
            if let debounceDelay {
                DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: work)
            } else {
                work.perform()
            }
        }

        private func renderPreviewInBackground(
            markdown: String,
            contentRevision: Int,
            baseURL: URL?,
            theme: PreviewTheme,
            scrollTarget: SourceLineScrollTarget?,
            requestID: Int,
            in webView: WKWebView
        ) {
            Self.previewRenderQueue.async { [weak self, weak webView] in
                let previewMarkdown = MarkdownPreviewView.markdownForPreviewRendering(markdown)
                let cacheKey = MarkdownPreviewRenderCache.Key(markdown: previewMarkdown, theme: theme)
                let html: String
                if let cachedHTML = MarkdownPreviewRenderCache.shared.html(for: cacheKey) {
                    PerformanceDiagnostics.shared.record(
                        "preview.render.cache_hit",
                        metadata: [
                            "characters": "\((markdown as NSString).length)",
                            "rendered_characters": "\((previewMarkdown as NSString).length)",
                            "theme": theme.rawValue,
                        ]
                    )
                    html = cachedHTML
                } else {
                    html = self?.renderPreviewHTML(
                        markdown: previewMarkdown,
                        originalMarkdown: markdown,
                        theme: theme
                    ) ?? ""
                    MarkdownPreviewRenderCache.shared.store(html: html, for: cacheKey)
                }

                DispatchQueue.main.async { [weak self, weak webView] in
                    guard
                        let self,
                        let webView,
                        self.previewReloadRequestID == requestID
                    else {
                        return
                    }

                    self.finishPreviewReload(
                        html: html,
                        markdown: previewMarkdown,
                        contentRevision: contentRevision,
                        baseURL: baseURL,
                        theme: theme,
                        scrollTarget: scrollTarget,
                        in: webView
                    )
                }
            }
        }

        private func reloadPreview(
            markdown: String,
            contentRevision: Int,
            baseURL: URL?,
            theme: PreviewTheme,
            scrollTarget: SourceLineScrollTarget?,
            in webView: WKWebView
        ) {
            let previewMarkdown = MarkdownPreviewView.markdownForPreviewRendering(markdown)
            let html = renderPreviewHTML(markdown: previewMarkdown, originalMarkdown: markdown, theme: theme)
            finishPreviewReload(
                html: html,
                markdown: previewMarkdown,
                contentRevision: contentRevision,
                baseURL: baseURL,
                theme: theme,
                scrollTarget: scrollTarget,
                in: webView
            )
        }

        private func renderPreviewHTML(markdown: String, originalMarkdown: String, theme: PreviewTheme) -> String {
            let originalCharacterCount = (originalMarkdown as NSString).length
            let renderedCharacterCount = (markdown as NSString).length
            return PerformanceDiagnostics.shared.measure(
                "preview.render",
                metadata: [
                    "characters": "\(originalCharacterCount)",
                    "rendered_characters": "\(renderedCharacterCount)",
                    "theme": theme.rawValue,
                ]
            ) {
                MarkdownRenderer.renderDocument(
                    markdown,
                    theme: theme,
                    enableExternalRenderers: MarkdownPreviewView.enablesExternalRenderers(for: originalMarkdown)
                )
            }
        }

        private func finishPreviewReload(
            html: String,
            markdown: String,
            contentRevision: Int,
            baseURL: URL?,
            theme: PreviewTheme,
            scrollTarget: SourceLineScrollTarget?,
            in webView: WKWebView
        ) {
            let shouldReuseLoadedPreview = MarkdownPreviewView.shouldReuseLoadedPreview(
                html: html,
                baseURL: baseURL,
                theme: theme,
                lastHTML: lastHTML,
                lastBaseURL: lastBaseURL,
                lastTheme: lastTheme,
                isPageLoaded: isPageLoaded
            )

            lastContentRevision = contentRevision
            lastHTML = html
            lastBaseURL = baseURL
            lastTheme = theme
            pendingPreviewReload = nil

            if shouldReuseLoadedPreview {
                if let scrollTarget {
                    applyScrollTarget(scrollTarget, in: webView)
                }
                return
            }

            previewReloadRevision += 1
            cancelPendingScrollSyncInstallRetry()
            isPageLoaded = false
            isScrollSyncInstalled = false
            scrollSyncInstallAttempt = 0
            lastAppliedScrollTarget = nil
            pendingScrollTarget = scrollTarget ?? lastVisibleSourceLine.map {
                SourceLineScrollTarget(line: $0, revision: previewReloadRevision)
            }
            PerformanceDiagnostics.shared.measure(
                "preview.load",
                metadata: ["html_characters": "\((html as NSString).length)"]
            ) {
                loadPreviewHTML(html, markdown: markdown, baseURL: baseURL, in: webView)
            }
        }

        func loadPreviewHTML(_ html: String, markdown: String, baseURL: URL?, in webView: WKWebView) {
            let htmlForPreview = MarkdownPreviewFileAccess.htmlWithBaseTag(html, baseURL: baseURL)

            do {
                let previewURL = try previewHTMLFileURL()
                try htmlForPreview.write(to: previewURL, atomically: true, encoding: .utf8)
                let readAccessURL = MarkdownPreviewFileAccess.readAccessURL(
                    baseURL: baseURL,
                    markdown: markdown,
                    htmlFileURL: previewURL
                )
                webView.loadFileURL(previewURL, allowingReadAccessTo: readAccessURL)
            } catch {
                webView.loadHTMLString(htmlForPreview, baseURL: baseURL)
            }
        }

        func applyScrollTarget(_ target: SourceLineScrollTarget, in webView: WKWebView) {
            guard isPageLoaded else {
                pendingScrollTarget = target
                return
            }
            guard lastAppliedScrollTarget != target else {
                return
            }

            pendingScrollReapply?.cancel()
            lastAppliedScrollTarget = target
            isApplyingProgrammaticScroll = true
            evaluateScrollTarget(target, in: webView)

            let reapplyWork = DispatchWorkItem { [weak self, weak webView] in
                guard
                    let self,
                    let webView,
                    self.lastAppliedScrollTarget == target
                else {
                    return
                }

                self.evaluateScrollTarget(target, in: webView)
                self.isApplyingProgrammaticScroll = false
            }
            pendingScrollReapply = reapplyWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: reapplyWork)
        }

        private func evaluateScrollTarget(_ target: SourceLineScrollTarget, in webView: WKWebView) {
            webView.evaluateJavaScript(MarkdownPreviewView.scrollTargetScript(for: target))
        }

        private func installScrollSyncScript(in webView: WKWebView) {
            cancelPendingScrollSyncInstallRetry()
            webView.evaluateJavaScript(Self.scrollSyncScript) { [weak self, weak webView] _, error in
                guard let self, let webView else {
                    return
                }

                if let error {
                    self.isScrollSyncInstalled = false
                    let nsError = error as NSError
                    PerformanceDiagnostics.shared.record(
                        "preview.scroll-sync.install_failed",
                        metadata: [
                            "attempt": "\(self.scrollSyncInstallAttempt + 1)",
                            "error_domain": nsError.domain,
                            "error_code": "\(nsError.code)",
                        ]
                    )

                    if let target = self.pendingScrollTarget {
                        self.pendingScrollTarget = nil
                        self.applyScrollTarget(target, in: webView)
                    }

                    guard
                        self.isPageLoaded,
                        let delay = MarkdownPreviewView.scrollSyncInstallRetryDelay(forAttempt: self.scrollSyncInstallAttempt)
                    else {
                        return
                    }

                    self.scrollSyncInstallAttempt += 1
                    let retry = DispatchWorkItem { [weak self, weak webView] in
                        guard let self, let webView else {
                            return
                        }
                        self.installScrollSyncScript(in: webView)
                    }
                    self.pendingScrollSyncInstallRetry = retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
                    return
                }

                self.scrollSyncInstallAttempt = 0
                self.isScrollSyncInstalled = true
                if let target = self.pendingScrollTarget {
                    self.pendingScrollTarget = nil
                    self.applyScrollTarget(target, in: webView)
                }
            }
        }

        private func configureNativeScrollObserver(in webView: WKWebView) {
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else {
                    return
                }
                guard let scrollView = Self.firstScrollView(in: webView) else {
                    return
                }
                guard observedScrollView !== scrollView else {
                    return
                }

                tearDownNativeScrollObserver()
                observedScrollView = scrollView
                scrollView.contentView.postsBoundsChangedNotifications = true
                nativeScrollObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self, weak webView] _ in
                    guard let self, let webView else {
                        return
                    }
                    self.scheduleNativeVisibleSourceLinePublish(in: webView)
                }
            }
        }

        private func scheduleNativeVisibleSourceLinePublish(in webView: WKWebView) {
            guard !isApplyingProgrammaticScroll else {
                return
            }

            pendingNativeScrollPublish?.cancel()
            let work = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else {
                    return
                }
                self.publishVisibleSourceLineFromPage(in: webView)
            }
            pendingNativeScrollPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        }

        private func publishVisibleSourceLineFromPage(in webView: WKWebView) {
            guard isPageLoaded, !isApplyingProgrammaticScroll else {
                return
            }

            let script = """
            (() => {
              if (window.moyeScrollSync && typeof window.moyeScrollSync.visibleSourceLine === 'function') {
                return window.moyeScrollSync.visibleSourceLine();
              }

              const blocks = Array.from(document.querySelectorAll('[data-source-line]'))
                .map((element) => ({
                  element,
                  line: Number.parseInt(element.getAttribute('data-source-line') || '1', 10)
                }))
                .filter((block) => Number.isFinite(block.line) && block.line > 0)
                .sort((left, right) => left.line - right.line);
              if (!blocks.length) {
                return 1;
              }

              const topThreshold = 24;
              let low = 0;
              let high = blocks.length - 1;
              let matchedIndex = 0;
              while (low <= high) {
                const mid = Math.floor((low + high) / 2);
                const block = blocks[mid];
                const rect = block.element.getBoundingClientRect();
                if (rect.top <= topThreshold) {
                  matchedIndex = mid;
                  low = mid + 1;
                } else {
                  high = mid - 1;
                }
              }
              return blocks[matchedIndex].line;
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self, !self.isApplyingProgrammaticScroll else {
                    return
                }

                let line: Int?
                if let number = result as? NSNumber {
                    line = number.intValue
                } else if let string = result as? String {
                    line = Int(string)
                } else {
                    line = nil
                }

                guard let line, line > 0 else {
                    return
                }
                self.publishSourceLine(line)
            }
        }

        private func publishSourceLine(_ line: Int) {
            guard line != lastVisibleSourceLine else {
                return
            }

            lastVisibleSourceLine = line
            DispatchQueue.main.async { [weak self] in
                self?.onVisibleSourceLineChange(line)
            }
        }

        private static func firstScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }

            for subview in view.subviews {
                if let scrollView = firstScrollView(in: subview) {
                    return scrollView
                }
            }

            return nil
        }

        private func previewHTMLFileURL() throws -> URL {
            let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            let folderURL = cachesURL.appendingPathComponent("MoyePreview", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            return folderURL.appendingPathComponent(previewFileName)
        }

        private static let scrollSyncScript = """
        (() => {
          if (window.moyeScrollSyncInstalled) {
            return;
          }

          window.moyeScrollSyncInstalled = true;

          let cachedBlocks = null;

          const blocks = () => {
            if (cachedBlocks) {
              return cachedBlocks;
            }

            cachedBlocks = Array.from(document.querySelectorAll('[data-source-line]'))
              .map((element) => ({
                element,
                line: Number.parseInt(element.getAttribute('data-source-line') || '1', 10)
              }))
              .filter((block) => Number.isFinite(block.line) && block.line > 0)
              .sort((left, right) => left.line - right.line);
            return cachedBlocks;
          };

          const nearestBlock = (line) => {
            const allBlocks = blocks();
            if (!allBlocks.length) {
              return null;
            }

            let candidate = allBlocks[0];
            for (const block of allBlocks) {
              if (block.line <= line) {
                candidate = block;
                continue;
              }

              if (Math.abs(block.line - line) < Math.abs(candidate.line - line)) {
                candidate = block;
              }
              break;
            }
            return candidate;
          };

          const sourceLineElementID = (line) => `moye-source-line-${Math.max(1, Number.parseInt(line, 10) || 1)}`;

          const scrollingElement = () => {
            return document.scrollingElement || document.documentElement || document.body;
          };

          const currentScrollTop = () => {
            const element = scrollingElement();
            return Math.max(
              element ? element.scrollTop || 0 : 0,
              window.pageYOffset || 0,
              window.scrollY || 0
            );
          };

          const scrollToY = (value) => {
            const top = Math.max(0, value);
            if (document.documentElement) {
              document.documentElement.scrollTop = top;
            }
            if (document.body) {
              document.body.scrollTop = top;
            }
            const element = scrollingElement();
            if (element) {
              element.scrollTop = top;
            }
            window.scrollTo({ top, left: window.scrollX || 0, behavior: 'auto' });
          };

          const visibleSourceLine = () => {
            const allBlocks = blocks();
            if (!allBlocks.length) {
              return 1;
            }

            const topThreshold = 24;
            let low = 0;
            let high = allBlocks.length - 1;
            let matchedIndex = 0;
            while (low <= high) {
              const mid = Math.floor((low + high) / 2);
              const block = allBlocks[mid];
              const rect = block.element.getBoundingClientRect();
              if (rect.top <= topThreshold) {
                matchedIndex = mid;
                low = mid + 1;
              } else {
                high = mid - 1;
              }
            }
            return allBlocks[matchedIndex].line;
          };

          let lastPublishedLine = null;
          let scrollTimer = null;
          let lastObservedScrollTop = currentScrollTop();

          const schedulePublish = () => {
            window.clearTimeout(scrollTimer);
            scrollTimer = window.setTimeout(publish, 60);
          };

          const publishIfScrollTopChanged = () => {
            const nextScrollTop = currentScrollTop();
            if (Math.abs(nextScrollTop - lastObservedScrollTop) < 1) {
              return;
            }

            lastObservedScrollTop = nextScrollTop;
            publish();
          };

          const publish = () => {
            if (window.moyeScrollSync.programmatic) {
              return;
            }

            const line = visibleSourceLine();
            if (line === lastPublishedLine) {
              return;
            }

            lastPublishedLine = line;
            window.webkit.messageHandlers.sourceLineScroll.postMessage(line);
          };

          window.moyeScrollSync = {
            programmatic: false,
            scrollToSourceLine(line, anchorID) {
              const parsedLine = Number.parseInt(line, 10);
              const requestedLine = Number.isFinite(parsedLine) && parsedLine > 0 ? parsedLine : 1;
              const anchorElement = anchorID ? document.getElementById(anchorID) : null;
              const exactSourceLineElement = document.getElementById(sourceLineElementID(requestedLine));
              const target = anchorElement
                ? { element: anchorElement, line: requestedLine }
                : exactSourceLineElement
                  ? { element: exactSourceLineElement, line: requestedLine }
                : nearestBlock(requestedLine);
              if (!target) {
                return { ok: false, reason: 'no-target' };
              }

              window.moyeScrollSync.programmatic = true;
              const topInset = 16;
              const targetTop = target.element.getBoundingClientRect().top + currentScrollTop() - topInset;
              scrollToY(targetTop);
              window.requestAnimationFrame(() => {
                scrollToY(targetTop);
              });
              window.setTimeout(() => {
                window.moyeScrollSync.programmatic = false;
                lastPublishedLine = visibleSourceLine();
              }, 250);
              return { ok: true, requestedLine, matchedLine: target.line, cached: true, exact: !!exactSourceLineElement };
            },
            visibleSourceLine
          };

          window.addEventListener('scroll', schedulePublish, { passive: true });
          window.addEventListener('wheel', schedulePublish, { passive: true, capture: true });
          document.addEventListener('scroll', schedulePublish, { passive: true, capture: true });
          document.addEventListener('wheel', schedulePublish, { passive: true, capture: true });
          const scrollElement = scrollingElement();
          if (scrollElement) {
            scrollElement.addEventListener('scroll', schedulePublish, { passive: true });
          }
          window.setInterval(publishIfScrollTopChanged, 180);
          window.setInterval(publish, 360);

          window.setTimeout(publish, 80);
        })();
        """
    }
}

final class MarkdownPreviewRenderCache {
    static let shared = MarkdownPreviewRenderCache()

    struct Key: Equatable {
        let theme: PreviewTheme
        let utf16Count: Int
        let utf8Count: Int
        let fingerprint: UInt64

        init(markdown: String, theme: PreviewTheme) {
            self.theme = theme
            utf16Count = markdown.utf16.count
            utf8Count = markdown.utf8.count
            fingerprint = Self.fingerprint(markdown)
        }

        private static func fingerprint(_ markdown: String) -> UInt64 {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in markdown.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            return hash
        }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let maximumEntryCount = 2

    private init() {}

    func html(for markdown: String, theme: PreviewTheme) -> String? {
        html(for: Key(markdown: markdown, theme: theme))
    }

    func html(for key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let index = entries.firstIndex(where: { $0.key == key }) else {
            return nil
        }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        return entry.html
    }

    func store(html: String, for markdown: String, theme: PreviewTheme) {
        store(html: html, for: Key(markdown: markdown, theme: theme))
    }

    func store(html: String, for key: Key) {
        lock.lock()
        entries.removeAll { $0.key == key }
        entries.insert(Entry(key: key, html: html), at: 0)
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }
        lock.unlock()
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    var retainedMarkdownCharacterCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.reduce(0) { $0 + $1.retainedMarkdownCharacterCount }
    }

    private struct Entry {
        let key: Key
        let html: String
        let retainedMarkdownCharacterCount = 0
    }
}

enum MarkdownPreviewFileAccess {
    static func htmlWithBaseTag(_ html: String, baseURL: URL?) -> String {
        guard let baseURL else {
            return html
        }

        let baseTag = #"<base href="\#(escapeHTMLAttribute(baseURL.absoluteString))">"#
        guard let headRange = html.range(of: "<head>") else {
            return baseTag + "\n" + html
        }

        var result = html
        result.replaceSubrange(headRange, with: "<head>\n  \(baseTag)")
        return result
    }

    static func readAccessURL(baseURL: URL?, markdown: String, htmlFileURL: URL) -> URL {
        var directories = [htmlFileURL.deletingLastPathComponent()]

        if let baseURL {
            directories.append(baseURL)
        }

        directories.append(contentsOf: localImageFileURLs(in: markdown, baseURL: baseURL).map { url in
            url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        })

        return commonAncestor(of: directories)
    }

    static func localImageFileURLs(in markdown: String, baseURL: URL?) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)\n]+)\)"#) else {
            return []
        }

        let nsMarkdown = markdown as NSString
        let range = NSRange(location: 0, length: nsMarkdown.length)
        return regex.matches(in: markdown, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else {
                return nil
            }

            let target = nsMarkdown.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return localFileURL(fromMarkdownTarget: target, baseURL: baseURL)
        }
    }

    private static func localFileURL(fromMarkdownTarget target: String, baseURL: URL?) -> URL? {
        let path = target.removingPercentEncoding ?? target
        let lowercased = path.lowercased()

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") || lowercased.hasPrefix("data:") {
            return nil
        }

        if lowercased.hasPrefix("file://") {
            return URL(string: path)
        }

        if path.hasPrefix("/") || path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }

        guard let baseURL else {
            return nil
        }

        return baseURL.appendingPathComponent(path)
    }

    private static func commonAncestor(of urls: [URL]) -> URL {
        let componentLists = urls
            .map { $0.standardizedFileURL.pathComponents }
            .filter { !$0.isEmpty }

        guard var commonComponents = componentLists.first else {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }

        for components in componentLists.dropFirst() {
            while
                !commonComponents.isEmpty &&
                !components.starts(with: commonComponents)
            {
                commonComponents.removeLast()
            }
        }

        guard !commonComponents.isEmpty else {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }

        let path = NSString.path(withComponents: commonComponents)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
