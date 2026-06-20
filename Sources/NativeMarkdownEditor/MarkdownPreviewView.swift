import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?
    let theme: PreviewTheme
    let scrollTarget: SourceLineScrollTarget?
    let onVisibleSourceLineChange: (Int) -> Void

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

        if
            markdown != context.coordinator.lastMarkdown ||
            baseURL != context.coordinator.lastBaseURL ||
            theme != context.coordinator.lastTheme ||
            context.coordinator.lastHTML == nil
        {
            let html = MarkdownRenderer.renderDocument(markdown, theme: theme)
            context.coordinator.isPageLoaded = false
            context.coordinator.isScrollSyncInstalled = false
            context.coordinator.lastAppliedScrollTarget = nil
            context.coordinator.pendingScrollTarget = scrollTarget
            context.coordinator.lastMarkdown = markdown
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            context.coordinator.lastTheme = theme
            context.coordinator.loadPreviewHTML(html, markdown: markdown, baseURL: baseURL, in: webView)
            return
        }

        if let scrollTarget {
            context.coordinator.applyScrollTarget(scrollTarget, in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageName = "sourceLineScroll"

        var lastMarkdown: String?
        var lastHTML: String?
        var lastBaseURL: URL?
        var lastTheme: PreviewTheme?
        var onVisibleSourceLineChange: (Int) -> Void
        var isPageLoaded = false
        var isScrollSyncInstalled = false
        var lastAppliedScrollTarget: SourceLineScrollTarget?
        var pendingScrollTarget: SourceLineScrollTarget?
        private var pendingScrollReapply: DispatchWorkItem?
        private var isApplyingProgrammaticScroll = false
        private let previewFileName = "preview-\(UUID().uuidString).html"

        init(onVisibleSourceLineChange: @escaping (Int) -> Void) {
            self.onVisibleSourceLineChange = onVisibleSourceLineChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            installScrollSyncScript(in: webView)
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

            DispatchQueue.main.async { [weak self] in
                self?.onVisibleSourceLineChange(line)
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
            guard isPageLoaded, isScrollSyncInstalled else {
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
            let line = max(1, target.line)
            let anchorLiteral = target.anchorID.map(Self.javaScriptStringLiteral) ?? "null"
            let script = """
            (() => {
              const requestedLine = \(line);
              const requestedAnchor = \(anchorLiteral);
              const blocks = Array.from(document.querySelectorAll('[data-source-line]'))
                .map((element) => ({
                  element,
                  line: Number.parseInt(element.getAttribute('data-source-line') || '1', 10)
                }))
                .filter((block) => Number.isFinite(block.line) && block.line > 0)
                  .sort((left, right) => left.line - right.line);

              const anchorElement = requestedAnchor ? document.getElementById(requestedAnchor) : null;
              if (!blocks.length && !anchorElement) {
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

              return { ok: true, requestedLine, matchedLine: target.line };
            })();
            """
            webView.evaluateJavaScript(script)
        }

        private static func javaScriptStringLiteral(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: #"\"#, with: #"\\"#)
                .replacingOccurrences(of: #"""#, with: #"\""#)
                .replacingOccurrences(of: "\n", with: #"\\n"#)
                .replacingOccurrences(of: "\r", with: #"\\r"#)
                .replacingOccurrences(of: "\u{2028}", with: #"\\u2028"#)
                .replacingOccurrences(of: "\u{2029}", with: #"\\u2029"#)
            return #""\#(escaped)""#
        }

        private func installScrollSyncScript(in webView: WKWebView) {
            webView.evaluateJavaScript(Self.scrollSyncScript) { [weak self, weak webView] _, _ in
                guard let self, let webView else {
                    return
                }

                self.isScrollSyncInstalled = true
                if let target = self.pendingScrollTarget {
                    self.pendingScrollTarget = nil
                    self.applyScrollTarget(target, in: webView)
                }
            }
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

            let current = allBlocks[0];
            const topThreshold = 24;
            for (const block of allBlocks) {
              const rect = block.element.getBoundingClientRect();
              if (rect.top <= topThreshold) {
                current = block;
              } else {
                break;
              }
            }
            return current.line;
          };

          let lastPublishedLine = null;
          let scrollTimer = null;

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
            scrollToSourceLine(line) {
              const target = nearestBlock(Number.parseInt(line, 10));
              if (!target) {
                return;
              }

              this.programmatic = true;
              const topInset = 16;
              const targetTop = target.element.getBoundingClientRect().top + currentScrollTop() - topInset;
              scrollToY(targetTop);
              window.requestAnimationFrame(() => {
                scrollToY(targetTop);
              });
              window.setTimeout(() => {
                this.programmatic = false;
                lastPublishedLine = visibleSourceLine();
              }, 250);
            },
            visibleSourceLine
          };

          window.addEventListener('scroll', () => {
            window.clearTimeout(scrollTimer);
            scrollTimer = window.setTimeout(publish, 60);
          }, { passive: true });

          window.setTimeout(publish, 80);
        })();
        """
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
