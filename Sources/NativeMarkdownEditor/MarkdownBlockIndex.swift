import Foundation

enum MarkdownBlockType: Equatable {
    case heading(level: Int)
    case paragraph
    case codeFence(language: String?)
    case table
    case list
    case blockquote
    case image
    case html
    case thematicBreak
}

struct MarkdownBlock: Identifiable, Equatable {
    let id: String
    let type: MarkdownBlockType
    let range: NSRange
    let lineRange: Range<Int>
    let source: String
    let revision: Int

    func shifted(characterDelta: Int, lineDelta: Int) -> MarkdownBlock {
        MarkdownBlock(
            id: id,
            type: type,
            range: NSRange(location: range.location + characterDelta, length: range.length),
            lineRange: (lineRange.lowerBound + lineDelta)..<(lineRange.upperBound + lineDelta),
            source: source,
            revision: revision
        )
    }
}

struct MarkdownTextEdit: Equatable {
    let oldRange: NSRange
    let newRange: NSRange
    let oldLength: Int
    let newLength: Int
    let lineDelta: Int

    var characterDelta: Int {
        newLength - oldLength
    }

    var touchesFenceBoundary: Bool {
        oldRange.length > 0 || newRange.length > 0
    }

    static func diff(old oldText: String, new newText: String) -> MarkdownTextEdit? {
        let oldNSString = oldText as NSString
        let newNSString = newText as NSString
        let oldLength = oldNSString.length
        let newLength = newNSString.length

        guard oldLength != newLength || oldText != newText else {
            return nil
        }

        var prefixLength = 0
        let sharedPrefixLimit = min(oldLength, newLength)
        while
            prefixLength < sharedPrefixLimit,
            oldNSString.character(at: prefixLength) == newNSString.character(at: prefixLength)
        {
            prefixLength += 1
        }

        var suffixLength = 0
        while
            suffixLength < oldLength - prefixLength,
            suffixLength < newLength - prefixLength,
            oldNSString.character(at: oldLength - suffixLength - 1) == newNSString.character(at: newLength - suffixLength - 1)
        {
            suffixLength += 1
        }

        return MarkdownTextEdit(
            oldRange: NSRange(location: prefixLength, length: oldLength - prefixLength - suffixLength),
            newRange: NSRange(location: prefixLength, length: newLength - prefixLength - suffixLength),
            oldLength: oldLength,
            newLength: newLength,
            lineDelta: countNewlines(
                in: newNSString,
                range: NSRange(location: prefixLength, length: newLength - prefixLength - suffixLength)
            ) - countNewlines(
                in: oldNSString,
                range: NSRange(location: prefixLength, length: oldLength - prefixLength - suffixLength)
            )
        )
    }

    private static func countNewlines(in string: NSString, range: NSRange) -> Int {
        guard range.length > 0 else {
            return 0
        }

        var count = 0
        let upperBound = min(string.length, NSMaxRange(range))
        guard range.location < upperBound else {
            return 0
        }

        for index in range.location..<upperBound {
            switch string.character(at: index) {
            case 10, 11, 12, 13, 0x85, 0x2028, 0x2029:
                count += 1
            default:
                continue
            }
        }
        return count
    }
}

struct MarkdownBlockIndex: Equatable {
    let blocks: [MarkdownBlock]
    let statistics: DocumentStatistics
    let outline: [OutlineItem]
    let markdownUTF16Length: Int
    let revision: Int

    init(markdown: String, revision: Int = 0) {
        let parsed = MarkdownBlockParser.parse(markdown: markdown, revision: revision)
        blocks = parsed.blocks
        statistics = parsed.statistics
        outline = parsed.outline
        markdownUTF16Length = (markdown as NSString).length
        self.revision = revision
    }

    private init(
        blocks: [MarkdownBlock],
        statistics: DocumentStatistics,
        outline: [OutlineItem],
        markdownUTF16Length: Int,
        revision: Int
    ) {
        self.blocks = blocks
        self.statistics = statistics
        self.outline = outline
        self.markdownUTF16Length = markdownUTF16Length
        self.revision = revision
    }

    func updating(markdown: String, edit: MarkdownTextEdit?, revision: Int) -> MarkdownBlockIndex {
        guard
            let edit,
            markdownUTF16Length == edit.oldLength,
            !blocks.isEmpty,
            !requiresFullReparse(for: edit)
        else {
            return MarkdownBlockIndex(markdown: markdown, revision: revision)
        }

        guard let affectedRange = affectedBlockRange(for: edit.oldRange) else {
            return MarkdownBlockIndex(markdown: markdown, revision: revision)
        }

        let firstAffectedBlock = blocks[affectedRange.lowerBound]
        let lastAffectedBlock = blocks[affectedRange.upperBound - 1]
        let oldParseRange = NSRange(
            location: firstAffectedBlock.range.location,
            length: NSMaxRange(lastAffectedBlock.range) - firstAffectedBlock.range.location
        )
        let newParseRange = NSRange(
            location: oldParseRange.location,
            length: max(0, oldParseRange.length + edit.characterDelta)
        )
        let newNSString = markdown as NSString
        guard NSMaxRange(newParseRange) <= newNSString.length else {
            return MarkdownBlockIndex(markdown: markdown, revision: revision)
        }

        let parsedReplacement = MarkdownBlockParser.parse(
            markdown: markdown,
            range: newParseRange,
            startingLine: firstAffectedBlock.lineRange.lowerBound,
            revision: revision
        )
        let oldLineCount = lastAffectedBlock.lineRange.upperBound - firstAffectedBlock.lineRange.lowerBound
        let newLineCount = parsedReplacement.lineCount
        let lineDelta = newLineCount - oldLineCount

        var nextBlocks: [MarkdownBlock] = []
        nextBlocks.reserveCapacity(blocks.count - affectedRange.count + parsedReplacement.blocks.count)
        nextBlocks.append(contentsOf: blocks[..<affectedRange.lowerBound])
        nextBlocks.append(contentsOf: parsedReplacement.blocks)
        nextBlocks.append(contentsOf: blocks[affectedRange.upperBound...].map {
            $0.shifted(characterDelta: edit.characterDelta, lineDelta: lineDelta)
        })

        let statistics = incrementalStatistics(
            replacing: affectedRange,
            parsedReplacement: parsedReplacement,
            edit: edit,
            newLength: newNSString.length
        )
        return MarkdownBlockIndex(
            blocks: nextBlocks,
            statistics: statistics,
            outline: MarkdownBlockParser.outline(from: nextBlocks),
            markdownUTF16Length: newNSString.length,
            revision: revision
        )
    }

    private func requiresFullReparse(for edit: MarkdownTextEdit) -> Bool {
        if edit.oldRange.length > 12_000 || edit.newRange.length > 12_000 {
            return true
        }

        for block in blocks where block.range.intersectsOrTouches(edit.oldRange) {
            if case .codeFence = block.type {
                return true
            }
        }

        return false
    }

    private func incrementalStatistics(
        replacing affectedRange: Range<Int>,
        parsedReplacement: MarkdownBlockParseResult,
        edit: MarkdownTextEdit,
        newLength: Int
    ) -> DocumentStatistics {
        let replacedWordCount = blocks[affectedRange].reduce(0) { partialResult, block in
            partialResult + DocumentStatistics(markdown: block.source).wordCount
        }
        return DocumentStatistics(
            wordCount: max(0, statistics.wordCount - replacedWordCount + parsedReplacement.statistics.wordCount),
            characterCount: newLength,
            lineCount: max(1, statistics.lineCount + edit.lineDelta)
        )
    }

    private func affectedBlockRange(for editRange: NSRange) -> Range<Int>? {
        guard let directRange = directlyAffectedBlockRange(for: editRange) else {
            return nil
        }

        let lowerBound = max(blocks.startIndex, directRange.lowerBound - 1)
        let upperBound = min(blocks.endIndex, directRange.upperBound + 1)
        return lowerBound..<upperBound
    }

    private func directlyAffectedBlockRange(for editRange: NSRange) -> Range<Int>? {
        let location = min(editRange.location, markdownUTF16Length)
        var first: Int?
        var last: Int?

        for index in blocks.indices {
            let range = blocks[index].range
            let intersects = editRange.length == 0
                ? range.containsOrTouches(location)
                : range.intersects(editRange)
            guard intersects else {
                continue
            }

            if first == nil {
                first = index
            }
            last = index
        }

        if let first, let last {
            return first..<(last + 1)
        }

        if let insertionIndex = blocks.lastIndex(where: { $0.range.location <= location }) {
            return insertionIndex..<(insertionIndex + 1)
        }

        return nil
    }
}

struct MarkdownBlockParseResult {
    let blocks: [MarkdownBlock]
    let statistics: DocumentStatistics
    let outline: [OutlineItem]
    let lineCount: Int
}

private struct MarkdownSourceLine {
    let text: String
    let contentRange: NSRange
    let enclosingRange: NSRange
    let number: Int
}

enum MarkdownBlockParser {
    static func parse(markdown: String, revision: Int = 0) -> MarkdownBlockParseResult {
        let nsMarkdown = markdown as NSString
        return parse(
            markdown: markdown,
            range: NSRange(location: 0, length: nsMarkdown.length),
            startingLine: 1,
            revision: revision,
            fullStatisticsMarkdown: markdown
        )
    }

    static func parse(
        markdown: String,
        range: NSRange,
        startingLine: Int,
        revision: Int
    ) -> MarkdownBlockParseResult {
        parse(
            markdown: markdown,
            range: range,
            startingLine: startingLine,
            revision: revision,
            fullStatisticsMarkdown: nil
        )
    }

    static func statistics(markdown: String) -> DocumentStatistics {
        DocumentStatistics(markdown: markdown)
    }

    static func outline(from blocks: [MarkdownBlock]) -> [OutlineItem] {
        blocks.compactMap { block in
            guard case let .heading(level) = block.type else {
                return nil
            }

            let title = headingTitle(from: block.source, level: level)
            guard !title.isEmpty else {
                return nil
            }

            return OutlineItem(
                id: "\(block.id)-outline",
                level: level,
                title: title,
                location: block.range.location,
                line: block.lineRange.lowerBound
            )
        }
    }

    private static func parse(
        markdown: String,
        range: NSRange,
        startingLine: Int,
        revision: Int,
        fullStatisticsMarkdown: String?
    ) -> MarkdownBlockParseResult {
        let nsMarkdown = markdown as NSString
        let lines = sourceLines(in: nsMarkdown, range: range, startingLine: startingLine)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = codeFenceMarker(in: trimmed) {
                let start = index
                index += 1
                while index < lines.count {
                    let candidate = lines[index].text.trimmingCharacters(in: .whitespaces)
                    defer { index += 1 }
                    if candidate.hasPrefix(fence.marker), candidate.allSatisfy({ $0 == "`" || $0 == "~" }) {
                        break
                    }
                }
                blocks.append(makeBlock(type: .codeFence(language: fence.language), lines: Array(lines[start..<index]), nsMarkdown: nsMarkdown, revision: revision))
                continue
            }

            if let level = headingLevel(in: trimmed) {
                blocks.append(makeBlock(type: .heading(level: level), lines: [line], nsMarkdown: nsMarkdown, revision: revision))
                index += 1
                continue
            }

            if isTableStart(at: index, lines: lines) {
                let start = index
                index += 1
                while index < lines.count, lines[index].text.contains("|"), !lines[index].text.trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                }
                blocks.append(makeBlock(type: .table, lines: Array(lines[start..<index]), nsMarkdown: nsMarkdown, revision: revision))
                continue
            }

            if isListLine(trimmed) {
                let start = index
                index += 1
                while index < lines.count {
                    let candidate = lines[index].text.trimmingCharacters(in: .whitespaces)
                    guard !candidate.isEmpty, isListLine(candidate) || candidate.hasPrefix("  ") || candidate.hasPrefix("\t") else {
                        break
                    }
                    index += 1
                }
                blocks.append(makeBlock(type: .list, lines: Array(lines[start..<index]), nsMarkdown: nsMarkdown, revision: revision))
                continue
            }

            if trimmed.hasPrefix(">") {
                let start = index
                index += 1
                while index < lines.count, lines[index].text.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    index += 1
                }
                blocks.append(makeBlock(type: .blockquote, lines: Array(lines[start..<index]), nsMarkdown: nsMarkdown, revision: revision))
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(makeBlock(type: .thematicBreak, lines: [line], nsMarkdown: nsMarkdown, revision: revision))
                index += 1
                continue
            }

            if trimmed.hasPrefix("![") {
                blocks.append(makeBlock(type: .image, lines: [line], nsMarkdown: nsMarkdown, revision: revision))
                index += 1
                continue
            }

            if trimmed.hasPrefix("<") {
                blocks.append(makeBlock(type: .html, lines: [line], nsMarkdown: nsMarkdown, revision: revision))
                index += 1
                continue
            }

            let start = index
            index += 1
            while index < lines.count {
                let candidate = lines[index].text.trimmingCharacters(in: .whitespaces)
                guard !candidate.isEmpty, !startsNewBlock(candidate, at: index, lines: lines) else {
                    break
                }
                index += 1
            }
            blocks.append(makeBlock(type: .paragraph, lines: Array(lines[start..<index]), nsMarkdown: nsMarkdown, revision: revision))
        }

        let statistics = fullStatisticsMarkdown.map(DocumentStatistics.init(markdown:)) ??
            DocumentStatistics(
                wordCount: blocks.reduce(0) { $0 + wordCount(in: $1.source) },
                characterCount: range.length,
                lineCount: max(1, lines.count)
            )

        return MarkdownBlockParseResult(
            blocks: blocks,
            statistics: statistics,
            outline: outline(from: blocks),
            lineCount: max(0, lines.count)
        )
    }

    private static func sourceLines(in nsMarkdown: NSString, range: NSRange, startingLine: Int) -> [MarkdownSourceLine] {
        guard range.length > 0 else {
            return []
        }

        var result: [MarkdownSourceLine] = []
        var lineNumber = startingLine
        nsMarkdown.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            result.append(MarkdownSourceLine(
                text: nsMarkdown.substring(with: substringRange),
                contentRange: substringRange,
                enclosingRange: enclosingRange,
                number: lineNumber
            ))
            lineNumber += 1
        }
        return result
    }

    private static func makeBlock(
        type: MarkdownBlockType,
        lines: [MarkdownSourceLine],
        nsMarkdown: NSString,
        revision: Int
    ) -> MarkdownBlock {
        let first = lines[0]
        let last = lines[lines.count - 1]
        let range = NSRange(
            location: first.enclosingRange.location,
            length: NSMaxRange(last.enclosingRange) - first.enclosingRange.location
        )
        return MarkdownBlock(
            id: "block-\(first.enclosingRange.location)-\(first.number)-\(revision)",
            type: type,
            range: range,
            lineRange: first.number..<(last.number + 1),
            source: nsMarkdown.substring(with: range),
            revision: revision
        )
    }

    private static func headingLevel(in trimmedLine: String) -> Int? {
        let markerCount = trimmedLine.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else {
            return nil
        }

        let index = trimmedLine.index(trimmedLine.startIndex, offsetBy: markerCount)
        guard index < trimmedLine.endIndex, trimmedLine[index] == " " else {
            return nil
        }
        return markerCount
    }

    private static func headingTitle(from source: String, level: Int) -> String {
        let firstLine: Substring
        if let newlineIndex = source.firstIndex(where: { $0.isNewline }) {
            firstLine = source[..<newlineIndex]
        } else {
            firstLine = source[...]
        }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let index = trimmed.index(trimmed.startIndex, offsetBy: min(level, trimmed.count))
        guard index < trimmed.endIndex else {
            return ""
        }
        return trimmed[index...].trimmingCharacters(in: .whitespaces)
    }

    private static func codeFenceMarker(in trimmedLine: String) -> (marker: String, language: String?)? {
        let marker: String
        if trimmedLine.hasPrefix("```") {
            marker = "```"
        } else if trimmedLine.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }

        let language = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func startsNewBlock(_ trimmedLine: String, at index: Int, lines: [MarkdownSourceLine]) -> Bool {
        headingLevel(in: trimmedLine) != nil ||
            codeFenceMarker(in: trimmedLine) != nil ||
            isTableStart(at: index, lines: lines) ||
            isListLine(trimmedLine) ||
            trimmedLine.hasPrefix(">") ||
            trimmedLine.hasPrefix("![") ||
            trimmedLine.hasPrefix("<") ||
            isThematicBreak(trimmedLine)
    }

    private static func isTableStart(at index: Int, lines: [MarkdownSourceLine]) -> Bool {
        guard index + 1 < lines.count else {
            return false
        }
        let current = lines[index].text
        let separator = lines[index + 1].text.trimmingCharacters(in: .whitespaces)
        return current.contains("|") && isTableSeparator(separator)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("|") else {
            return false
        }

        var hasSeparatorCell = false
        var currentCell = ""

        func consumeCurrentCell() {
            let trimmed = currentCell.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" || $0 == ":" }) {
                hasSeparatorCell = true
            }
            currentCell.removeAll(keepingCapacity: true)
        }

        for character in line {
            if character == "|" {
                consumeCurrentCell()
            } else {
                currentCell.append(character)
            }
        }
        consumeCurrentCell()
        return hasSeparatorCell
    }

    private static func isListLine(_ trimmedLine: String) -> Bool {
        if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
            return true
        }
        if trimmedLine.hasPrefix("- [ ] ") || trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
            return true
        }

        var digits = ""
        for character in trimmedLine {
            if character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }
        guard !digits.isEmpty else {
            return false
        }
        let rest = trimmedLine.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private static func isThematicBreak(_ trimmedLine: String) -> Bool {
        let compact = trimmedLine.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else {
            return false
        }
        return compact.allSatisfy { $0 == "-" } ||
            compact.allSatisfy { $0 == "*" } ||
            compact.allSatisfy { $0 == "_" }
    }

    private static func wordCount(in text: String) -> Int {
        DocumentStatistics(markdown: text).wordCount
    }
}

private extension NSRange {
    func intersects(_ other: NSRange) -> Bool {
        NSIntersectionRange(self, other).length > 0
    }

    func intersectsOrTouches(_ other: NSRange) -> Bool {
        let lower = max(location, other.location)
        let upper = min(NSMaxRange(self), NSMaxRange(other))
        return lower <= upper
    }

    func containsOrTouches(_ location: Int) -> Bool {
        location >= self.location && location <= NSMaxRange(self)
    }
}
