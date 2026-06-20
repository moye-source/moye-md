import Foundation

struct TextBufferEdit: Equatable {
    let oldRange: NSRange
    let newRange: NSRange
    let oldFragment: String
    let newFragment: String
    let oldLength: Int
    let newLength: Int
    let lineDelta: Int

    var markdownTextEdit: MarkdownTextEdit {
        MarkdownTextEdit(
            oldRange: oldRange,
            newRange: newRange,
            oldLength: oldLength,
            newLength: newLength,
            lineDelta: lineDelta
        )
    }
}

final class PieceTableTextBuffer {
    private enum PieceSource: Equatable {
        case original
        case add
    }

    private struct Piece: Equatable {
        let source: PieceSource
        var start: Int
        var length: Int
    }

    private var originalStorage: String
    private var addStorage: String
    private var pieces: [Piece]
    private(set) var lineIndex: SourceLineIndex
    private(set) var length: Int

    init(_ text: String = "") {
        originalStorage = text
        addStorage = ""
        length = (text as NSString).length
        pieces = length > 0 ? [Piece(source: .original, start: 0, length: length)] : []
        lineIndex = SourceLineIndex(text: text)
    }

    var text: String {
        string(from: pieces)
    }

    var pieceCount: Int {
        pieces.count
    }

    func reset(_ text: String) {
        originalStorage = text
        addStorage = ""
        length = (text as NSString).length
        pieces = length > 0 ? [Piece(source: .original, start: 0, length: length)] : []
        lineIndex = SourceLineIndex(text: text)
    }

    func substring(with range: NSRange) -> String? {
        guard isValidRange(range) else {
            return nil
        }
        guard range.length > 0 else {
            return ""
        }

        let targetEnd = NSMaxRange(range)
        var cursor = 0
        var result = ""
        result.reserveCapacity(range.length)

        let original = originalStorage as NSString
        let added = addStorage as NSString
        for piece in pieces {
            let pieceStart = cursor
            let pieceEnd = cursor + piece.length
            defer { cursor = pieceEnd }

            guard pieceEnd > range.location, pieceStart < targetEnd else {
                continue
            }

            let overlapStart = max(pieceStart, range.location)
            let overlapEnd = min(pieceEnd, targetEnd)
            let offsetInPiece = overlapStart - pieceStart
            let storage = piece.source == .original ? original : added
            result += storage.substring(
                with: NSRange(
                    location: piece.start + offsetInPiece,
                    length: overlapEnd - overlapStart
                )
            )
        }

        return result
    }

    @discardableResult
    func replaceCharacters(in range: NSRange, with replacement: String) -> TextBufferEdit? {
        guard isValidRange(range), let oldFragment = substring(with: range) else {
            return nil
        }

        let replacementLength = (replacement as NSString).length
        let oldLength = length
        let newLength = oldLength - range.length + replacementLength
        let newRange = NSRange(location: range.location, length: replacementLength)

        let prefix = piecesPrefix(upTo: range.location)
        let suffix = piecesSuffix(from: NSMaxRange(range))
        var replacementPieces: [Piece] = []
        if replacementLength > 0 {
            let addStart = (addStorage as NSString).length
            addStorage += replacement
            replacementPieces.append(Piece(source: .add, start: addStart, length: replacementLength))
        }

        pieces = Self.coalesced(prefix + replacementPieces + suffix)
        length = newLength

        let sourceEdit = SourceLineIndexEdit(range: range, replacement: replacement)
        lineIndex = lineIndex.updating(with: sourceEdit, newTextLength: newLength) ?? SourceLineIndex(text: text)

        return TextBufferEdit(
            oldRange: range,
            newRange: newRange,
            oldFragment: oldFragment,
            newFragment: replacement,
            oldLength: oldLength,
            newLength: newLength,
            lineDelta: Self.countNewlines(in: replacement) - Self.countNewlines(in: oldFragment)
        )
    }

    private func isValidRange(_ range: NSRange) -> Bool {
        range.location >= 0 &&
            range.length >= 0 &&
            range.location <= length &&
            NSMaxRange(range) <= length
    }

    private func piecesPrefix(upTo offset: Int) -> [Piece] {
        guard offset > 0 else {
            return []
        }

        var cursor = 0
        var result: [Piece] = []
        result.reserveCapacity(pieces.count)

        for piece in pieces {
            let pieceStart = cursor
            let pieceEnd = cursor + piece.length
            defer { cursor = pieceEnd }

            if pieceEnd <= offset {
                result.append(piece)
                continue
            }

            if pieceStart < offset {
                result.append(Piece(
                    source: piece.source,
                    start: piece.start,
                    length: offset - pieceStart
                ))
            }
            break
        }

        return result
    }

    private func piecesSuffix(from offset: Int) -> [Piece] {
        guard offset < length else {
            return []
        }

        var cursor = 0
        var result: [Piece] = []
        result.reserveCapacity(pieces.count)

        for piece in pieces {
            let pieceStart = cursor
            let pieceEnd = cursor + piece.length
            defer { cursor = pieceEnd }

            if pieceEnd <= offset {
                continue
            }

            if pieceStart >= offset {
                result.append(piece)
                continue
            }

            let offsetInPiece = offset - pieceStart
            result.append(Piece(
                source: piece.source,
                start: piece.start + offsetInPiece,
                length: piece.length - offsetInPiece
            ))
        }

        return result
    }

    private func string(from pieces: [Piece]) -> String {
        guard !pieces.isEmpty else {
            return ""
        }

        let original = originalStorage as NSString
        let added = addStorage as NSString
        var result = ""
        result.reserveCapacity(length)
        for piece in pieces where piece.length > 0 {
            let storage = piece.source == .original ? original : added
            result += storage.substring(with: NSRange(location: piece.start, length: piece.length))
        }
        return result
    }

    private static func coalesced(_ pieces: [Piece]) -> [Piece] {
        var result: [Piece] = []
        result.reserveCapacity(pieces.count)

        for piece in pieces where piece.length > 0 {
            if
                let last = result.last,
                last.source == piece.source,
                last.start + last.length == piece.start
            {
                result[result.count - 1] = Piece(
                    source: last.source,
                    start: last.start,
                    length: last.length + piece.length
                )
            } else {
                result.append(piece)
            }
        }

        return result
    }

    private static func countNewlines(in text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        let nsText = text as NSString
        var count = 0
        for index in 0..<nsText.length {
            switch nsText.character(at: index) {
            case 10, 11, 12, 13, 0x85, 0x2028, 0x2029:
                count += 1
            default:
                continue
            }
        }
        return count
    }
}
