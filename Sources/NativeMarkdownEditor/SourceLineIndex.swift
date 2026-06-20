import Foundation

struct SourceLineIndexEdit: Equatable {
    let range: NSRange
    let replacement: String
}

struct SourceLineIndex: Equatable {
    private let lineStarts: [Int]
    private let textLength: Int
    private let visualLineCountCache: SourceLineIndexVisualLineCountCache

    init(text: String) {
        let nsString = text as NSString
        textLength = nsString.length

        var starts = [0]
        starts.reserveCapacity(max(1, textLength / 80))
        if textLength > 0 {
            for index in 0..<textLength where nsString.character(at: index) == 10 {
                starts.append(min(index + 1, textLength))
            }
        }
        lineStarts = starts
        visualLineCountCache = SourceLineIndexVisualLineCountCache()
    }

    private init(
        lineStarts: [Int],
        textLength: Int,
        visualLineCountCache: SourceLineIndexVisualLineCountCache = SourceLineIndexVisualLineCountCache()
    ) {
        self.lineStarts = lineStarts
        self.textLength = textLength
        self.visualLineCountCache = visualLineCountCache
    }

    static func == (lhs: SourceLineIndex, rhs: SourceLineIndex) -> Bool {
        lhs.lineStarts == rhs.lineStarts && lhs.textLength == rhs.textLength
    }

    var lineCount: Int {
        max(1, lineStarts.count)
    }

    var characterCount: Int {
        textLength
    }

    var cachedEstimatedVisualLineCountWidthCountForTesting: Int {
        visualLineCountCache.count
    }

    func lineNumber(at characterIndex: Int) -> Int {
        let index = min(max(0, characterIndex), textLength)
        var lower = 0
        var upper = lineStarts.count

        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= index {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        return max(1, lower)
    }

    func range(forLine line: Int) -> NSRange {
        let lineIndex = min(max(0, line - 1), max(0, lineStarts.count - 1))
        let start = lineStarts[lineIndex]
        let end = lineIndex + 1 < lineStarts.count ? lineStarts[lineIndex + 1] : textLength
        return NSRange(location: start, length: max(0, end - start))
    }

    func estimatedVisualLineCount(charactersPerVisualLine: Int) -> Int {
        let charactersPerVisualLine = max(1, charactersPerVisualLine)
        if let cached = visualLineCountCache.value(for: charactersPerVisualLine) {
            return cached
        }

        var count = 0

        for lineIndex in lineStarts.indices {
            count += Self.visualLineCount(
                at: lineIndex,
                lineStarts: lineStarts,
                textLength: textLength,
                charactersPerVisualLine: charactersPerVisualLine
            )
        }

        let clampedCount = max(1, count)
        visualLineCountCache.store(clampedCount, for: charactersPerVisualLine)
        return clampedCount
    }

    func updating(with edit: SourceLineIndexEdit, newTextLength: Int) -> SourceLineIndex? {
        guard edit.range.location >= 0, edit.range.length >= 0 else {
            return nil
        }
        guard NSMaxRange(edit.range) <= textLength else {
            return nil
        }

        let replacementLength = (edit.replacement as NSString).length
        guard textLength - edit.range.length + replacementLength == newTextLength else {
            return nil
        }

        let replacedRangeEnd = NSMaxRange(edit.range)
        let characterDelta = replacementLength - edit.range.length
        var nextStarts: [Int] = []
        nextStarts.reserveCapacity(lineStarts.count + 4)

        for start in lineStarts {
            if start == 0 || start <= edit.range.location {
                nextStarts.append(start)
            }
        }

        let replacement = edit.replacement as NSString
        if replacementLength > 0 {
            for index in 0..<replacementLength where replacement.character(at: index) == 10 {
                nextStarts.append(edit.range.location + index + 1)
            }
        }

        for start in lineStarts where start > replacedRangeEnd {
            nextStarts.append(start + characterDelta)
        }

        var compactedStarts: [Int] = []
        compactedStarts.reserveCapacity(nextStarts.count)
        for start in nextStarts where start >= 0 && start <= newTextLength {
            guard compactedStarts.last != start else {
                continue
            }
            compactedStarts.append(start)
        }

        if compactedStarts.first != 0 {
            compactedStarts.insert(0, at: 0)
        }

        let nextCache = visualLineCountCache.updating(
            oldLineStarts: lineStarts,
            oldTextLength: textLength,
            edit: edit,
            newLineStarts: compactedStarts,
            newTextLength: newTextLength
        )
        return SourceLineIndex(
            lineStarts: compactedStarts,
            textLength: newTextLength,
            visualLineCountCache: nextCache
        )
    }

    fileprivate static func lineIndex(
        at characterIndex: Int,
        lineStarts: [Int],
        textLength: Int
    ) -> Int {
        guard !lineStarts.isEmpty else {
            return 0
        }

        let index = min(max(0, characterIndex), textLength)
        var lower = 0
        var upper = lineStarts.count

        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= index {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        return min(max(0, lower - 1), lineStarts.count - 1)
    }

    fileprivate static func visualLineCount(
        at lineIndex: Int,
        lineStarts: [Int],
        textLength: Int,
        charactersPerVisualLine: Int
    ) -> Int {
        let start = lineStarts[lineIndex]
        let end = lineIndex + 1 < lineStarts.count ? lineStarts[lineIndex + 1] : textLength
        let contentLength = max(0, end - start - (lineIndex + 1 < lineStarts.count ? 1 : 0))
        return max(1, Int(ceil(Double(max(1, contentLength)) / Double(charactersPerVisualLine))))
    }
}

private final class SourceLineIndexVisualLineCountCache {
    private var counts: [Int: Int]

    init(counts: [Int: Int] = [:]) {
        self.counts = counts
    }

    var count: Int {
        counts.count
    }

    func value(for charactersPerVisualLine: Int) -> Int? {
        counts[charactersPerVisualLine]
    }

    func store(_ count: Int, for charactersPerVisualLine: Int) {
        counts[charactersPerVisualLine] = count
    }

    func updating(
        oldLineStarts: [Int],
        oldTextLength: Int,
        edit: SourceLineIndexEdit,
        newLineStarts: [Int],
        newTextLength: Int
    ) -> SourceLineIndexVisualLineCountCache {
        guard !counts.isEmpty else {
            return SourceLineIndexVisualLineCountCache()
        }

        let replacementLength = (edit.replacement as NSString).length
        let oldStartLine = SourceLineIndex.lineIndex(
            at: edit.range.location,
            lineStarts: oldLineStarts,
            textLength: oldTextLength
        )
        let oldEndLine = SourceLineIndex.lineIndex(
            at: NSMaxRange(edit.range),
            lineStarts: oldLineStarts,
            textLength: oldTextLength
        )
        let newStartLine = SourceLineIndex.lineIndex(
            at: edit.range.location,
            lineStarts: newLineStarts,
            textLength: newTextLength
        )
        let newEndLine = SourceLineIndex.lineIndex(
            at: edit.range.location + replacementLength,
            lineStarts: newLineStarts,
            textLength: newTextLength
        )

        var nextCounts: [Int: Int] = [:]
        nextCounts.reserveCapacity(counts.count)
        for (charactersPerVisualLine, previousCount) in counts {
            let oldAffectedCount = Self.visualLineCount(
                lineRange: oldStartLine...oldEndLine,
                lineStarts: oldLineStarts,
                textLength: oldTextLength,
                charactersPerVisualLine: charactersPerVisualLine
            )
            let newAffectedCount = Self.visualLineCount(
                lineRange: newStartLine...newEndLine,
                lineStarts: newLineStarts,
                textLength: newTextLength,
                charactersPerVisualLine: charactersPerVisualLine
            )
            nextCounts[charactersPerVisualLine] = max(
                1,
                previousCount - oldAffectedCount + newAffectedCount
            )
        }

        return SourceLineIndexVisualLineCountCache(counts: nextCounts)
    }

    private static func visualLineCount(
        lineRange: ClosedRange<Int>,
        lineStarts: [Int],
        textLength: Int,
        charactersPerVisualLine: Int
    ) -> Int {
        guard !lineStarts.isEmpty else {
            return 1
        }

        let lowerBound = max(0, lineRange.lowerBound)
        let upperBound = min(lineStarts.count - 1, lineRange.upperBound)
        guard lowerBound <= upperBound else {
            return 0
        }

        var count = 0
        for lineIndex in lowerBound...upperBound {
            count += SourceLineIndex.visualLineCount(
                at: lineIndex,
                lineStarts: lineStarts,
                textLength: textLength,
                charactersPerVisualLine: charactersPerVisualLine
            )
        }
        return count
    }
}
