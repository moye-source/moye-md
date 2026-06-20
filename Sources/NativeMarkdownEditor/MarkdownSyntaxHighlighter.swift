import AppKit

enum MarkdownSyntaxHighlighter {
    static let fullHighlightCharacterLimit = 250_000

    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private static let strongFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    static func usesFullHighlighting(characterCount: Int) -> Bool {
        characterCount <= fullHighlightCharacterLimit
    }

    static func paragraphStyleForEditor() -> NSParagraphStyle {
        paragraphStyle()
    }

    static func apply(to textView: NSTextView, focusRange: NSRange? = nil) {
        guard !textView.hasMarkedText() else {
            return
        }

        guard let storage = textView.textStorage else {
            return
        }

        let nsString = storage.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        guard fullRange.length > 0 else {
            textView.typingAttributes = baseAttributes()
            return
        }

        guard usesFullHighlighting(characterCount: nsString.length) else {
            textView.font = baseFont
            textView.textColor = .textColor
            textView.typingAttributes = baseAttributes()
            return
        }

        let selectedRanges = textView.selectedRanges
        let undoManager = textView.undoManager
        let undoWasEnabled = undoManager?.isUndoRegistrationEnabled ?? false

        if undoWasEnabled {
            undoManager?.disableUndoRegistration()
        }

        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: fullRange)

        let codeBlockRanges = fencedCodeRanges(in: storage.string)
        applyCodeBlockStyle(to: storage, ranges: codeBlockRanges)
        applyFrontMatterStyle(to: storage)
        applyLineStyles(to: storage, skipping: codeBlockRanges)
        applyInlineStyles(to: storage, skipping: codeBlockRanges)
        applyFocusStyle(to: storage, focusRange: focusRange)

        storage.endEditing()

        if undoWasEnabled {
            undoManager?.enableUndoRegistration()
        }

        textView.typingAttributes = baseAttributes()
        textView.selectedRanges = selectedRanges.clampedSelectionRanges(toLength: nsString.length)
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return style
    }

    private static func applyCodeBlockStyle(to storage: NSTextStorage, ranges: [NSRange]) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .backgroundColor: NSColor.textColor.withAlphaComponent(0.06),
            .paragraphStyle: paragraphStyle(),
        ]

        for range in ranges {
            storage.addAttributes(attributes, range: range)
        }
    }

    private static func applyFrontMatterStyle(to storage: NSTextStorage) {
        let string = storage.string as NSString
        guard string.length > 0 else {
            return
        }

        guard let range = storage.string.firstMatchRange(pattern: #"(?s)\A---\n.*?\n---"#) else {
            return
        }

        storage.addAttributes([
            .foregroundColor: NSColor.secondaryLabelColor,
            .backgroundColor: NSColor.textColor.withAlphaComponent(0.05),
        ], range: range)
    }

    private static func applyLineStyles(to storage: NSTextStorage, skipping codeBlockRanges: [NSRange]) {
        apply(pattern: #"^(#{1,6})[ \t]+(.+)$"#, to: storage, skipping: codeBlockRanges) { storage, match in
            let lineRange = match.range(at: 0)
            let markerRange = match.range(at: 1)

            storage.addAttributes([
                .font: strongFont,
                .foregroundColor: NSColor.labelColor,
            ], range: lineRange)
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
            ], range: markerRange)
        }

        apply(pattern: #"^>[ \t]?.*$"#, to: storage, skipping: codeBlockRanges) { storage, match in
            let lineRange = match.range(at: 0)
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: lineRange)
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
            ], range: NSRange(location: lineRange.location, length: 1))
        }

        apply(pattern: #"^[ \t]*([-*+])[ \t]+"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
                .font: strongFont,
            ], range: match.range(at: 1))
        }

        apply(pattern: #"^[ \t]*(\d+\.)[ \t]+"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
                .font: strongFont,
            ], range: match.range(at: 1))
        }

        apply(pattern: #"^[ \t]*[-*+][ \t]+(\[[ xX]\])"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemGreen,
                .font: strongFont,
            ], range: match.range(at: 1))
        }

        apply(pattern: #"^[ \t]*\|.*\|[ \t]*$"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"^\[TOC\]$"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemPurple,
                .font: strongFont,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"^[-*_][ \t]*[-*_][ \t]*[-*_][-*_\t ]*$"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.tertiaryLabelColor,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"^\[\^([^\]]+)\]:\s+.*$"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: match.range(at: 0))
            storage.addAttributes([
                .foregroundColor: NSColor.systemPurple,
                .font: strongFont,
            ], range: match.range(at: 1))
        }
    }

    private static func applyInlineStyles(to storage: NSTextStorage, skipping codeBlockRanges: [NSRange]) {
        apply(pattern: #"`[^`\n]+`"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.textColor.withAlphaComponent(0.07),
            ], range: match.range(at: 0))
        }

        apply(pattern: #"\*\*([^*\n]+)\*\*"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .font: strongFont,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"__([^_\n]+)__"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .font: strongFont,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .font: italicFont(),
            ], range: match.range(at: 0))
        }

        apply(pattern: #"(?<!_)_([^_\n]+)_(?!_)"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .font: italicFont(),
            ], range: match.range(at: 0))
        }

        apply(pattern: #"!?\[[^\]\n]+\]\([^) \n]+\)"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemPurple,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"~~([^~\n]+)~~"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            ], range: match.range(at: 0))
        }

        apply(pattern: #"==([^=\n]+)=="#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35),
            ], range: match.range(at: 0))
        }

        apply(pattern: #"\[\^([^\]]+)\]"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .foregroundColor: NSColor.systemPurple,
                .baselineOffset: 4,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            ], range: match.range(at: 0))
        }

        apply(pattern: #"(?<!\^)\^([^\^\n]+)\^(?!\^)"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .baselineOffset: 5,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            ], range: match.range(at: 0))
        }

        apply(pattern: #"(?<!~)~([^~\n]+)~(?!~)"#, to: storage, skipping: codeBlockRanges) { storage, match in
            storage.addAttributes([
                .baselineOffset: -3,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            ], range: match.range(at: 0))
        }
    }

    private static func applyFocusStyle(to storage: NSTextStorage, focusRange: NSRange?) {
        guard let focusRange else {
            return
        }

        let nsString = storage.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        guard let safeFocusRange = focusRange.clamped(toLength: nsString.length) else {
            return
        }

        let lineRange = nsString.lineRange(for: safeFocusRange)
        let dimAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.45),
        ]

        let beforeRange = NSRange(location: 0, length: lineRange.location)
        let afterStart = NSMaxRange(lineRange)
        let afterRange = NSRange(location: afterStart, length: max(0, fullRange.length - afterStart))

        if beforeRange.length > 0 {
            storage.addAttributes(dimAttributes, range: beforeRange)
        }
        if afterRange.length > 0 {
            storage.addAttributes(dimAttributes, range: afterRange)
        }
    }

    private static func apply(
        pattern: String,
        to storage: NSTextStorage,
        skipping skippedRanges: [NSRange],
        body: (NSTextStorage, NSTextCheckingResult) -> Void
    ) {
        guard let regex = RegexCache.expression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return
        }

        let string = storage.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        regex.enumerateMatches(in: string, options: [], range: fullRange) { match, _, _ in
            guard let match else {
                return
            }
            guard !intersects(match.range(at: 0), skippedRanges) else {
                return
            }
            body(storage, match)
        }
    }

    private static func fencedCodeRanges(in text: String) -> [NSRange] {
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        var ranges: [NSRange] = []
        var openFenceLocation: Int?

        nsString.enumerateSubstrings(in: fullRange, options: [.byLines]) { line, _, enclosingRange, _ in
            guard let line else {
                return
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let start = openFenceLocation {
                    let end = enclosingRange.location + enclosingRange.length
                    ranges.append(NSRange(location: start, length: end - start))
                    openFenceLocation = nil
                } else {
                    openFenceLocation = enclosingRange.location
                }
            }
        }

        if let start = openFenceLocation {
            ranges.append(NSRange(location: start, length: nsString.length - start))
        }

        return ranges
    }

    private static func intersects(_ range: NSRange, _ candidates: [NSRange]) -> Bool {
        candidates.contains { candidate in
            NSIntersectionRange(range, candidate).length > 0
        }
    }

    private static func italicFont() -> NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }
}

private extension String {
    func firstMatchRange(pattern: String) -> NSRange? {
        guard let regex = RegexCache.expression(pattern: pattern) else {
            return nil
        }

        let fullRange = NSRange(startIndex..<endIndex, in: self)
        return regex.firstMatch(in: self, options: [], range: fullRange)?.range(at: 0)
    }
}
