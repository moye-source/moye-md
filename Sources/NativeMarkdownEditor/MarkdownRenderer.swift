import Foundation

enum MarkdownRenderer {
    static func renderDocument(
        _ markdown: String,
        theme: PreviewTheme = .system,
        includeStyles: Bool = true,
        enableExternalRenderers: Bool = true
    ) -> String {
        let context = RenderContext(markdown: markdown)

        return """
        <!doctype html>
        <html class="\(theme.cssClass)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          \(includeStyles ? defaultStyles() : "")
          \(enableExternalRenderers ? externalRendererHeadScripts() : "")
        </head>
        <body>
        \(renderBody(markdown, context: context))
        \(renderFootnotes(context))
        \(enableExternalRenderers ? externalRendererBodyScripts() : "")
        </body>
        </html>
        """
    }

    private static func defaultStyles() -> String {
        """
        <style>
          :root {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            line-height: 1.56;
            --page-bg: Canvas;
            --text: CanvasText;
            --muted: color-mix(in srgb, CanvasText 72%, transparent);
            --soft: color-mix(in srgb, CanvasText 9%, transparent);
            --rule: color-mix(in srgb, CanvasText 18%, transparent);
            --accent: #286ee6;
            --quote: #6b8afd;
          }
          html.theme-system { color-scheme: light dark; }
          html.theme-light {
            color-scheme: light;
            --page-bg: #ffffff;
            --text: #1f2328;
            --muted: #59636e;
            --soft: #eff2f5;
            --rule: #d8dee4;
            --accent: #0969da;
            --quote: #3b78e7;
          }
          html.theme-dark {
            color-scheme: dark;
            --page-bg: #111316;
            --text: #eceff4;
            --muted: #aeb7c2;
            --soft: #242a31;
            --rule: #333b45;
            --accent: #7aa2ff;
            --quote: #8da2fb;
          }
          html.theme-sepia {
            color-scheme: light;
            --page-bg: #fbf3df;
            --text: #3f3426;
            --muted: #77664f;
            --soft: #eadfc8;
            --rule: #dac9aa;
            --accent: #8b551f;
            --quote: #b16a2a;
          }
          body {
            margin: 0;
            padding: 28px 34px 64px;
            color: var(--text);
            background: var(--page-bg);
          }
          h1, h2, h3, h4, h5, h6 {
            line-height: 1.2;
            margin: 1.2em 0 0.45em;
          }
          h1 { font-size: 2rem; border-bottom: 1px solid var(--rule); padding-bottom: 0.25em; }
          h2 { font-size: 1.45rem; }
          h3 { font-size: 1.2rem; }
          p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
          ul, ol { padding-left: 1.45em; }
          li.task-list-item { list-style: none; margin-left: -1.2em; }
          li.task-list-item input { margin-right: 0.55em; }
          blockquote {
            border-left: 4px solid var(--quote);
            padding-left: 1em;
            color: var(--muted);
          }
          code, pre {
            font-family: "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.92em;
          }
          code {
            padding: 0.12em 0.32em;
            border-radius: 4px;
            background: var(--soft);
          }
          pre {
            padding: 14px 16px;
            overflow: auto;
            border-radius: 8px;
            background: var(--soft);
          }
          pre code {
            padding: 0;
            background: transparent;
          }
          figure.code-block {
            margin: 0 0 1em;
          }
          .code-block pre {
            margin: 0;
            border-radius: 0 0 8px 8px;
          }
          .code-title {
            display: flex;
            align-items: center;
            gap: 0.55em;
            border-radius: 8px 8px 0 0;
            border-bottom: 1px solid var(--rule);
            padding: 8px 12px;
            background: color-mix(in srgb, var(--soft) 74%, var(--page-bg));
            color: var(--muted);
            font-size: 0.82em;
            font-weight: 650;
          }
          .code-icon {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 1.45em;
            height: 1.45em;
            border-radius: 4px;
            color: #111316;
            background: #8fc7ff;
            font-size: 0.8em;
            font-family: "SF Mono", Menlo, Consolas, monospace;
          }
          .code-icon-swift { background: #ff8a4c; }
          .code-icon-ts, .code-icon-js { background: #6db9ff; }
          .code-icon-python { background: #ffd45f; }
          .code-icon-bash { background: #9ee37d; }
          .code-icon-json { background: #d6c96b; }
          .code-icon-yaml, .code-icon-toml { background: #bda4ff; }
          .code-icon-nginx { background: #79d78b; }
          .code-icon-dockerfile { background: #7ec7ff; }
          .code-icon-sql { background: #95d4ff; }
          a { color: var(--accent); }
          mark { background: #fff2a8; color: #2f2600; padding: 0.05em 0.2em; border-radius: 3px; }
          img {
            display: block;
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            margin: 0.35em 0 1em;
          }
          hr { border: none; border-top: 1px solid var(--rule); margin: 2em 0; }
          table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.95em;
          }
          th, td {
            border: 1px solid var(--rule);
            padding: 8px 10px;
            text-align: left;
            vertical-align: top;
          }
          th { background: var(--soft); }
          .front-matter {
            color: var(--muted);
            border: 1px solid var(--rule);
            border-radius: 8px;
            padding: 12px 14px;
            margin-bottom: 1.2em;
            background: var(--soft);
          }
          .front-matter summary { cursor: pointer; font-weight: 600; }
          .front-matter pre { margin: 0.8em 0 0; background: transparent; padding: 0; }
          .toc {
            border: 1px solid var(--rule);
            border-radius: 8px;
            padding: 14px 16px;
            margin-bottom: 1.4em;
          }
          .toc-title { font-weight: 700; margin-bottom: 0.5em; }
          .toc ul { margin: 0; padding-left: 1.2em; }
          .toc-level-1 { margin-left: 0; }
          .toc-level-2 { margin-left: 1em; }
          .toc-level-3, .toc-level-4, .toc-level-5, .toc-level-6 { margin-left: 2em; }
          .footnotes {
            border-top: 1px solid var(--rule);
            color: var(--muted);
            font-size: 0.9em;
            margin-top: 2.4em;
            padding-top: 1em;
          }
          .math-block {
            overflow-x: auto;
            padding: 0.35em 0;
          }
          .diagram {
            overflow-x: auto;
            text-align: center;
          }
          .diagram-fallback {
            border: 1px dashed var(--rule);
            border-radius: 8px;
            padding: 12px 14px;
            color: var(--muted);
            background: var(--soft);
            text-align: left;
          }
        </style>
        """
    }

    private static func externalRendererHeadScripts() -> String {
        """
        <script>
          window.MathJax = {
            tex: {
              inlineMath: [['$', '$']],
              displayMath: [['$$', '$$']],
              processEscapes: true
            },
            svg: { fontCache: 'global' }
          };
        </script>
        <script defer src="https://cdn.jsdelivr.net/npm/mathjax@4/tex-svg.js"></script>
        """
    }

    private static func externalRendererBodyScripts() -> String {
        """
        <script type="module">
          const nodes = document.querySelectorAll('.diagram.mermaid');
          if (nodes.length) {
            import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs')
              .then(async ({ default: mermaid }) => {
                mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'strict' });
                await mermaid.run({ nodes, suppressErrors: true });
              })
              .catch(() => {
                nodes.forEach((node) => node.classList.add('diagram-fallback'));
              });
          }
        </script>
        """
    }

    private static func sourceLineAttribute(_ lineIndex: Int) -> String {
        #" data-source-line="\#(lineIndex + 1)""#
    }

    private static func renderBody(_ markdown: String, context: RenderContext) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html: [String] = []
        var paragraph: [String] = []
        var paragraphStartLineIndex: Int?
        var codeLines: [String] = []
        var codeFenceLanguage: String?
        var codeFenceStartLineIndex: Int?
        var isInCodeFence = false
        var isInUnorderedList = false
        var isInOrderedList = false
        var lineIndex = 0

        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            let attribute = sourceLineAttribute(paragraphStartLineIndex ?? 0)
            html.append("<p\(attribute)>\(paragraph.map { renderInline($0, context: context) }.joined(separator: " "))</p>")
            paragraph.removeAll()
            paragraphStartLineIndex = nil
        }

        func closeLists() {
            if isInUnorderedList {
                html.append("</ul>")
                isInUnorderedList = false
            }
            if isInOrderedList {
                html.append("</ol>")
                isInOrderedList = false
            }
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if lineIndex == 0, let frontMatter = parseFrontMatter(lines: lines) {
                closeParagraph()
                closeLists()
                html.append(renderFrontMatter(frontMatter.content, sourceLine: lineIndex))
                lineIndex = frontMatter.consumedLineCount
                continue
            }

            if context.shouldSkipLine(at: lineIndex) {
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                closeParagraph()
                closeLists()

                if isInCodeFence {
                    html.append(renderCodeFence(
                        language: codeFenceLanguage,
                        lines: codeLines,
                        sourceLine: codeFenceStartLineIndex ?? lineIndex
                    ))
                    codeLines.removeAll()
                    codeFenceLanguage = nil
                    codeFenceStartLineIndex = nil
                    isInCodeFence = false
                } else {
                    codeFenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeFenceStartLineIndex = lineIndex
                    isInCodeFence = true
                }
                lineIndex += 1
                continue
            }

            if isInCodeFence {
                codeLines.append(line)
                lineIndex += 1
                continue
            }

            if trimmed.isEmpty {
                closeParagraph()
                closeLists()
                lineIndex += 1
                continue
            }

            if let mathBlock = parseMathBlock(lines: lines, startIndex: lineIndex) {
                closeParagraph()
                closeLists()
                html.append(renderMathBlock(mathBlock.content, sourceLine: lineIndex))
                lineIndex += mathBlock.consumedLineCount
                continue
            }

            if isHorizontalRule(trimmed) {
                closeParagraph()
                closeLists()
                html.append("<hr\(sourceLineAttribute(lineIndex))>")
                lineIndex += 1
                continue
            }

            if trimmed.lowercased() == "[toc]" {
                closeParagraph()
                closeLists()
                html.append(renderTOC(context.headings, sourceLine: lineIndex))
                lineIndex += 1
                continue
            }

            if let table = parseTable(lines: lines, startIndex: lineIndex, context: context, sourceLine: lineIndex) {
                closeParagraph()
                closeLists()
                html.append(table.html)
                lineIndex += table.consumedLineCount
                continue
            }

            if let heading = parseHeading(trimmed) {
                closeParagraph()
                closeLists()
                let id = headingAnchorID(for: heading.text)
                html.append("<h\(heading.level)\(sourceLineAttribute(lineIndex)) id=\"\(id)\">\(renderInline(heading.text, context: context))</h\(heading.level)>")
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                closeParagraph()
                closeLists()
                let quote = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                html.append("<blockquote\(sourceLineAttribute(lineIndex))>\(renderInline(String(quote), context: context))</blockquote>")
                lineIndex += 1
                continue
            }

            if let item = parseUnorderedListItem(trimmed) {
                closeParagraph()
                if isInOrderedList {
                    html.append("</ol>")
                    isInOrderedList = false
                }
                if !isInUnorderedList {
                    html.append("<ul\(sourceLineAttribute(lineIndex))>")
                    isInUnorderedList = true
                }
                html.append(renderListItem(item, context: context, sourceLine: lineIndex))
                lineIndex += 1
                continue
            }

            if let item = parseOrderedListItem(trimmed) {
                closeParagraph()
                if isInUnorderedList {
                    html.append("</ul>")
                    isInUnorderedList = false
                }
                if !isInOrderedList {
                    html.append("<ol\(sourceLineAttribute(lineIndex))>")
                    isInOrderedList = true
                }
                html.append(renderListItem(item, context: context, sourceLine: lineIndex))
                lineIndex += 1
                continue
            }

            closeLists()
            if paragraphStartLineIndex == nil {
                paragraphStartLineIndex = lineIndex
            }
            paragraph.append(trimmed)
            lineIndex += 1
        }

        closeParagraph()
        closeLists()

        if isInCodeFence {
            html.append(renderCodeFence(
                language: codeFenceLanguage,
                lines: codeLines,
                sourceLine: codeFenceStartLineIndex ?? lineIndex
            ))
        }

        return html.joined(separator: "\n")
    }

    fileprivate static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else { return nil }

        let index = line.index(line.startIndex, offsetBy: markerCount)
        guard index < line.endIndex, line[index] == " " else { return nil }

        let text = line[index...].trimmingCharacters(in: .whitespaces)
        return (markerCount, text)
    }

    private static func parseFrontMatter(lines: [String]) -> (content: String, consumedLineCount: Int)? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        var frontMatter: [String] = []
        var index = 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                return (frontMatter.joined(separator: "\n"), index + 1)
            }
            frontMatter.append(lines[index])
            index += 1
        }

        return nil
    }

    private static func renderFrontMatter(_ content: String, sourceLine: Int) -> String {
        """
        <details class="front-matter"\(sourceLineAttribute(sourceLine))>
        <summary>YAML Front Matter</summary>
        <pre><code>\(escapeHTML(content))</code></pre>
        </details>
        """
    }

    private static func parseMathBlock(lines: [String], startIndex: Int) -> (content: String, consumedLineCount: Int)? {
        guard lines[startIndex].trimmingCharacters(in: .whitespaces) == "$$" else {
            return nil
        }

        var content: [String] = []
        var index = startIndex + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "$$" {
                return (content.joined(separator: "\n"), index - startIndex + 1)
            }
            content.append(lines[index])
            index += 1
        }

        return nil
    }

    private static func renderMathBlock(_ content: String, sourceLine: Int) -> String {
        """
        <div class="math-block"\(sourceLineAttribute(sourceLine))>
        $$\(escapeHTML(content))$$
        </div>
        """
    }

    private static func renderCodeFence(language: String?, lines: [String], sourceLine: Int) -> String {
        let code = escapeHTML(lines.joined(separator: "\n"))
        let normalizedLanguage = language?.lowercased()

        if normalizedLanguage == "mermaid" {
            return """
            <pre class="diagram mermaid"\(sourceLineAttribute(sourceLine))>\(code)</pre>
            """
        }

        if ["sequence", "flow"].contains(normalizedLanguage ?? "") {
            let title = "\(normalizedLanguage ?? "Diagram") diagram"
            return """
            <div class="diagram-fallback"\(sourceLineAttribute(sourceLine))>
            <strong>\(title)</strong>
            <pre><code>\(code)</code></pre>
            </div>
            """
        }

        let normalized = normalizedLanguage?.isEmpty == false ? normalizedLanguage! : "text"
        let languageClass = #" class="language-\#(normalized)""#
        let title = languageTitle(normalized)
        let icon = languageIcon(normalized)
        return """
        <figure class="code-block"\(sourceLineAttribute(sourceLine))>
        <figcaption class="code-title"><span class="code-icon code-icon-\(normalized)">\(icon)</span><span>\(title)</span></figcaption>
        <pre><code\(languageClass)>\(code)</code></pre>
        </figure>
        """
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.range(of: #"^([-*_])(\s*\1){2,}\s*$"#, options: .regularExpression) != nil
    }

    private static func renderTOC(_ headings: [Heading], sourceLine: Int) -> String {
        guard !headings.isEmpty else {
            return #"<nav class="toc"\#(sourceLineAttribute(sourceLine))><div class="toc-title">Table of Contents</div><p>No headings found.</p></nav>"#
        }

        let items = headings
            .map { heading in
                "<li class=\"toc-level-\(heading.level)\"><a href=\"#\(heading.id)\">\(escapeHTML(heading.title))</a></li>"
            }
            .joined(separator: "\n")

        return """
        <nav class="toc"\(sourceLineAttribute(sourceLine))>
        <div class="toc-title">Table of Contents</div>
        <ul>
        \(items)
        </ul>
        </nav>
        """
    }

    private static func renderFootnotes(_ context: RenderContext) -> String {
        guard !context.footnoteOrder.isEmpty else {
            return ""
        }

        let items = context.footnoteOrder.enumerated()
            .compactMap { index, id -> String? in
                guard let text = context.footnotes[id] else {
                    return nil
                }
                return "<li id=\"fn-\(id)\">\(renderInline(text, context: context)) <a href=\"#fnref-\(id)\">&#8617;</a></li>"
            }
            .joined(separator: "\n")

        return """
        <section class="footnotes">
        <ol>
        \(items)
        </ol>
        </section>
        """
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        guard line.count > 2 else { return nil }
        let prefixes = ["- ", "* ", "+ "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func parseOrderedListItem(_ line: String) -> String? {
        guard let match = line.firstMatch(pattern: #"^\d+\.\s+(.+)$"#) else { return nil }
        return match
    }

    private static func renderListItem(_ item: String, context: RenderContext?, sourceLine: Int) -> String {
        if let task = parseTaskItem(item) {
            let checked = task.isChecked ? " checked" : ""
            return #"<li class="task-list-item"\#(sourceLineAttribute(sourceLine))><input type="checkbox" disabled\#(checked)> \#(renderInline(task.text, context: context))</li>"#
        }

        return "<li\(sourceLineAttribute(sourceLine))>\(renderInline(item, context: context))</li>"
    }

    private static func parseTaskItem(_ item: String) -> (isChecked: Bool, text: String)? {
        guard let match = item.firstMatchGroups(pattern: #"^\[([ xX])\]\s+(.+)$"#), match.count == 2 else {
            return nil
        }

        return (match[0].lowercased() == "x", match[1])
    }

    private static func parseTable(
        lines: [String],
        startIndex: Int,
        context: RenderContext?,
        sourceLine: Int
    ) -> (html: String, consumedLineCount: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|"), isTableSeparator(separatorLine) else {
            return nil
        }

        let headers = splitTableRow(headerLine)
        guard !headers.isEmpty else {
            return nil
        }

        var rows: [[String]] = []
        var currentIndex = startIndex + 2
        while currentIndex < lines.count {
            let line = lines[currentIndex].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else {
                break
            }
            rows.append(splitTableRow(line))
            currentIndex += 1
        }

        let headerHTML = headers
                .map { "<th>\(renderInline($0, context: context))</th>" }
            .joined()
        let bodyHTML = rows
            .map { row in
                let cells = normalized(row, count: headers.count)
                    .map { "<td>\(renderInline($0, context: context))</td>" }
                    .joined()
                return "<tr>\(cells)</tr>"
            }
            .joined(separator: "\n")

        return (
            """
            <table\(sourceLineAttribute(sourceLine))>
            <thead><tr>\(headerHTML)</tr></thead>
            <tbody>
            \(bodyHTML)
            </tbody>
            </table>
            """,
            currentIndex - startIndex
        )
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let parts = splitTableRow(line)
        guard !parts.isEmpty else {
            return false
        }

        return parts.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var row = line
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
        if row.count >= count {
            return Array(row.prefix(count))
        }

        return row + Array(repeating: "", count: count - row.count)
    }

    static func headingAnchorID(for text: String) -> String {
        let lowercased = text.lowercased()
        let allowed = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(String(scalar))
            }
            return "-"
        }
        let slug = String(allowed)
            .replacing(pattern: #"-+"#, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "heading" : slug
    }

    private static func renderEmojiShortcodes(_ html: String) -> String {
        let emojiMap = [
            ":smile:": "😄",
            ":happy:": "😄",
            ":laughing:": "😆",
            ":heart:": "❤️",
            ":thumbsup:": "👍",
            ":+1:": "👍",
            ":warning:": "⚠️",
            ":check:": "✅",
            ":x:": "❌",
        ]

        return emojiMap.reduce(html) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    private static func preserveInlineHTML(in html: String) -> String {
        html
            .replacing(pattern: #"&lt;(\/?(?:u|br|kbd|sub|sup|mark|small|span|video|iframe)\b[^&]*)&gt;"#, with: #"<$1>"#)
    }

    private static func renderInline(_ text: String, context: RenderContext?) -> String {
        var protectedHTML: [String] = []

        func token(for index: Int) -> String {
            "MOYEINLINEHTMLTOKEN\(index)END"
        }

        func protect(_ html: String) -> String {
            let index = protectedHTML.count
            protectedHTML.append(html)
            return token(for: index)
        }

        var escaped = escapeHTML(text)
            .replacingMatches(pattern: #"`([^`]+)`"#) { groups in
                guard let code = groups.first else { return nil }
                return protect("<code>\(code)</code>")
            }
            .replacingMatches(pattern: #"!\[([^\]]*)\]\(([^)\n]+)\)"#) { groups in
                guard groups.count == 2 else { return nil }
                return protect(renderImage(alt: groups[0], target: groups[1]))
            }
            .replacingMatches(pattern: #"\[([^\]]+)\]\[([^\]]*)\]"#) { groups in
                guard let label = groups[safe: 1], let reference = context?.referenceLinks[label.isEmpty ? groups[0] : label] else {
                    return nil
                }
                return protect(#"<a href="\#(normalizedResourceURL(reference.url))"\#(reference.titleAttribute)>\#(groups[0])</a>"#)
            }
            .replacingMatches(pattern: #"\[([^\]]+)\]\(([^)\n]+)\)"#) { groups in
                guard groups.count == 2 else { return nil }
                let target = splitResourceTarget(groups[1])
                return protect(#"<a href="\#(normalizedResourceURL(target.url))"\#(titleAttribute(target.title))>\#(groups[0])</a>"#)
            }
            .replacingMatches(pattern: #"(?<!\S)(https?://[^\s<]+)"#) { groups in
                guard let url = groups.first else { return nil }
                return protect(#"<a href="\#(normalizedResourceURL(url))">\#(url)</a>"#)
            }
            .replacingMatches(pattern: #"(?<!\S)(www\.[^\s<]+)"#) { groups in
                guard let url = groups.first else { return nil }
                return protect(#"<a href="https://\#(url)">\#(url)</a>"#)
            }
            .replacingMatches(pattern: #"\[\^([^\]]+)\]"#) { groups in
                guard let id = groups.first, context?.footnotes[id] != nil else {
                    return nil
                }
                return protect("<sup id=\"fnref-\(id)\"><a href=\"#fn-\(id)\">\(context?.footnoteNumber(for: id) ?? 0)</a></sup>")
            }
            .replacing(pattern: #"\*\*([^*\n]+)\*\*"#, with: #"<strong>$1</strong>"#)
            .replacing(pattern: #"__([^_\n]+)__"#, with: #"<strong>$1</strong>"#)
            .replacing(pattern: #"~~([^~\n]+)~~"#, with: #"<del>$1</del>"#)
            .replacing(pattern: #"==([^=\n]+)=="#, with: #"<mark>$1</mark>"#)
            .replacing(pattern: #"(?<!\^)\^([^\^\n]+)\^(?!\^)"#, with: #"<sup>$1</sup>"#)
            .replacing(pattern: #"(?<!~)~([^~\n]+)~(?!~)"#, with: #"<sub>$1</sub>"#)
            .replacing(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, with: #"<em>$1</em>"#)
            .replacing(pattern: #"(?<!_)_([^_\n]+)_(?!_)"#, with: #"<em>$1</em>"#)

        escaped = preserveInlineHTML(in: escaped)
        escaped = renderEmojiShortcodes(escaped)

        for (index, html) in protectedHTML.enumerated() {
            escaped = escaped.replacingOccurrences(of: token(for: index), with: html)
        }

        return escaped
    }

    private static func renderImage(alt: String, target: String) -> String {
        let splitTarget = splitResourceTarget(target)
        let title = titleAttribute(splitTarget.title)
        return #"<img src="\#(normalizedResourceURL(splitTarget.url))" alt="\#(alt)"\#(title)>"#
    }

    private static func splitResourceTarget(_ target: String) -> (url: String, title: String?) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let groups = trimmed.firstMatchGroups(pattern: #"^(.+?)\s+&quot;([^&]*)&quot;$"#), groups.count == 2 {
            return (groups[0], groups[1])
        }
        if let groups = trimmed.firstMatchGroups(pattern: #"^(.+?)\s+&#39;([^&]*)&#39;$"#), groups.count == 2 {
            return (groups[0], groups[1])
        }
        return (trimmed, nil)
    }

    private static func titleAttribute(_ title: String?) -> String {
        guard let title, !title.isEmpty else {
            return ""
        }
        return #" title="\#(title)""#
    }

    private static func normalizedResourceURL(_ rawValue: String) -> String {
        let raw = unescapeHTMLAttribute(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let lowercased = raw.lowercased()

        if lowercased.hasPrefix("data:") {
            return escapeHTML(raw)
        }

        if lowercased.hasPrefix("file://") {
            return escapeHTML(raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? raw)
        }

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return escapeHTML(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw)
        }

        if raw.hasPrefix("/") || raw.hasPrefix("~") {
            let path = (raw as NSString).expandingTildeInPath.removingPercentEncoding ?? (raw as NSString).expandingTildeInPath
            return escapeHTML(URL(fileURLWithPath: path).absoluteString)
        }

        return escapeHTML(raw.addingPercentEncoding(withAllowedCharacters: .markdownResourceAllowed) ?? raw)
    }

    private static func unescapeHTMLAttribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func languageTitle(_ language: String) -> String {
        switch language {
        case "swift":
            "Swift"
        case "ts", "typescript":
            "TypeScript"
        case "js", "javascript":
            "JavaScript"
        case "py", "python":
            "Python"
        case "sh", "shell", "bash", "zsh":
            "Shell"
        case "json":
            "JSON"
        case "yaml", "yml":
            "YAML"
        case "toml":
            "TOML"
        case "nginx":
            "Nginx"
        case "dockerfile":
            "Dockerfile"
        case "sql":
            "SQL"
        default:
            language.uppercased()
        }
    }

    private static func languageIcon(_ language: String) -> String {
        switch language {
        case "swift":
            "S"
        case "ts", "typescript":
            "TS"
        case "js", "javascript":
            "JS"
        case "py", "python":
            "Py"
        case "sh", "shell", "bash", "zsh":
            "$"
        case "json":
            "{}"
        case "yaml", "yml":
            "Y"
        case "toml":
            "T"
        case "nginx":
            "N"
        case "dockerfile":
            "D"
        case "sql":
            "SQL"
        default:
            "</>"
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private extension CharacterSet {
    static var markdownResourceAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "#?&=%")
        return allowed
    }
}

private struct Heading {
    let level: Int
    let title: String
    let id: String
}

private struct ReferenceLink {
    let url: String
    let title: String?

    var titleAttribute: String {
        guard let title, !title.isEmpty else {
            return ""
        }
        return #" title="\#(title)""#
    }
}

private struct RenderContext {
    let headings: [Heading]
    let footnotes: [String: String]
    let footnoteOrder: [String]
    let referenceLinks: [String: ReferenceLink]
    private let skippedLineIndexes: Set<Int>

    init(markdown: String) {
        let lines = markdown.components(separatedBy: .newlines)
        var headings: [Heading] = []
        var footnotes: [String: String] = [:]
        var footnoteOrder: [String] = []
        var referenceLinks: [String: ReferenceLink] = [:]
        var skippedLineIndexes: Set<Int> = []
        var isInCodeFence = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInCodeFence.toggle()
                continue
            }

            guard !isInCodeFence else {
                continue
            }

            if let footnote = trimmed.firstMatchGroups(pattern: #"^\[\^([^\]]+)\]:\s*(.+)$"#), footnote.count == 2 {
                footnotes[footnote[0]] = footnote[1]
                footnoteOrder.append(footnote[0])
                skippedLineIndexes.insert(index)
                continue
            }

            if let reference = trimmed.firstMatchGroups(pattern: #"^\[([^\]]+)\]:\s+(\S+)(?:\s+&quot;([^&]*)&quot;|\s+"([^"]*)")?\s*$"#) {
                let title = reference.count > 2 ? reference.dropFirst(2).first(where: { !$0.isEmpty }) : nil
                referenceLinks[reference[0]] = ReferenceLink(url: reference[1], title: title)
                skippedLineIndexes.insert(index)
                continue
            }

            if let heading = MarkdownRenderer.parseHeading(trimmed) {
                headings.append(Heading(
                    level: heading.level,
                    title: heading.text,
                    id: MarkdownRenderer.headingAnchorID(for: heading.text)
                ))
            }
        }

        self.headings = headings
        self.footnotes = footnotes
        self.footnoteOrder = footnoteOrder
        self.referenceLinks = referenceLinks
        self.skippedLineIndexes = skippedLineIndexes
    }

    func shouldSkipLine(at index: Int) -> Bool {
        skippedLineIndexes.contains(index)
    }

    func footnoteNumber(for id: String) -> Int {
        guard let index = footnoteOrder.firstIndex(of: id) else {
            return 0
        }
        return index + 1
    }
}

private extension String {
    func replacing(pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: template
        )
    }

    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard
            let match = regex.firstMatch(in: self, options: [], range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }

        return String(self[captureRange])
    }

    func firstMatchGroups(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range) else {
            return nil
        }

        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let captureRange = Range(range, in: self) else {
                groups.append("")
                continue
            }
            groups.append(String(self[captureRange]))
        }

        return groups
    }

    func replacingMatches(pattern: String, transform: ([String]) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }

        let nsString = self as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: self, options: [], range: fullRange).reversed()
        var result = self

        for match in matches {
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                guard range.location != NSNotFound else {
                    groups.append("")
                    continue
                }
                groups.append(nsString.substring(with: range))
            }

            guard let replacement = transform(groups) else {
                continue
            }

            if let swiftRange = Range(match.range(at: 0), in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }

        return result
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
