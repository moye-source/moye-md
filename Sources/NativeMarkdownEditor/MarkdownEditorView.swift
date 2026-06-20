import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let focusModeEnabled: Bool
    let typewriterModeEnabled: Bool
    let lineNumbersEnabled: Bool
    let autoPairEnabled: Bool
    let scrollTarget: SourceLineScrollTarget?
    let onVisibleSourceLineChange: (Int) -> Void
    let onInsertImageURLs: ([URL]) -> Void
    let onPasteImage: (NSPasteboard) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedRange: $selectedRange,
            focusModeEnabled: focusModeEnabled,
            typewriterModeEnabled: typewriterModeEnabled,
            autoPairEnabled: autoPairEnabled,
            onVisibleSourceLineChange: onVisibleSourceLineChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MarkdownEditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView(frame: .zero)
        let initialContentSize = scrollView.contentSize
        let initialTextWidth = max(initialContentSize.width, 640)
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: initialTextWidth,
            height: max(initialContentSize.height, 400)
        )
        textView.delegate = context.coordinator
        textView.string = text
        if let safeRange = selectedRange.clamped(toLength: (text as NSString).length) {
            context.coordinator.isApplyingExternalUpdate = true
            textView.setSelectedRange(safeRange)
            context.coordinator.rememberSelectionAppliedFromBinding(safeRange)
            context.coordinator.isApplyingExternalUpdate = false
        }
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 18, height: 18)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.insertImageURLs = onInsertImageURLs
        textView.pasteImage = onPasteImage
        textView.registerForDraggedTypes([.fileURL])

        textView.minSize = NSSize(width: 0, height: initialContentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: initialTextWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        let coordinator = context.coordinator
        scrollView.onVisibleBoundsChange = { [weak coordinator] in
            coordinator?.publishVisibleSourceLine()
        }
        context.coordinator.textView = textView
        configureLineNumbers(for: scrollView, textView: textView, enabled: lineNumbersEnabled)
        context.coordinator.applySyntaxHighlighting(to: textView)
        Self.updateTextContainerGeometry(for: scrollView, textView: textView)
        DispatchQueue.main.async { [weak scrollView, weak textView] in
            guard let scrollView, let textView else {
                return
            }
            Self.updateTextContainerGeometry(for: scrollView, textView: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        context.coordinator.focusModeEnabled = focusModeEnabled
        context.coordinator.typewriterModeEnabled = typewriterModeEnabled
        context.coordinator.autoPairEnabled = autoPairEnabled
        context.coordinator.onVisibleSourceLineChange = onVisibleSourceLineChange
        Self.updateTextContainerGeometry(for: scrollView, textView: textView)
        configureLineNumbers(for: scrollView, textView: textView, enabled: lineNumbersEnabled)
        let pendingScrollTarget = scrollTarget.flatMap { target in
            context.coordinator.shouldApplyScrollTarget(target) ? target : nil
        }

        if textView.string != text {
            guard !textView.hasMarkedText() else {
                return
            }

            let selectedRanges = textView.selectedRanges
            let textLength = (text as NSString).length
            context.coordinator.isApplyingExternalUpdate = true
            textView.string = text
            textView.selectedRanges = selectedRanges.clampedSelectionRanges(
                toLength: textLength,
                fallback: selectedRange
            )
            context.coordinator.isApplyingExternalUpdate = false
        }

        if
            !textView.hasMarkedText(),
            let safeRange = selectedRange.clamped(toLength: (textView.string as NSString).length),
            context.coordinator.shouldApplySelectionFromBinding(safeRange, to: textView)
        {
            context.coordinator.isApplyingExternalUpdate = true
            textView.setSelectedRange(safeRange)
            if pendingScrollTarget == nil {
                textView.scrollRangeToVisible(safeRange)
            }
            context.coordinator.rememberSelectionAppliedFromBinding(safeRange)
            context.coordinator.isApplyingExternalUpdate = false
        }

        context.coordinator.applySyntaxHighlighting(to: textView)
        Self.updateTextContainerGeometry(for: scrollView, textView: textView)

        if let pendingScrollTarget {
            context.coordinator.applyScrollTarget(pendingScrollTarget)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var selectedRange: Binding<NSRange>
        weak var textView: NSTextView?
        var isApplyingExternalUpdate = false
        var focusModeEnabled: Bool
        var typewriterModeEnabled: Bool
        var autoPairEnabled: Bool
        var onVisibleSourceLineChange: (Int) -> Void
        private var lastSelectionPublishedToSwiftUI: NSRange?
        private var isApplyingSyntaxHighlighting = false
        private var isApplyingScrollTarget = false
        private var lastAppliedScrollTarget: SourceLineScrollTarget?
        private var lastPublishedVisibleSourceLine: Int?
        private var lastHighlightedText: String?
        private var lastHighlightedFocusRange: NSRange?
        private var pendingScrollReapply: DispatchWorkItem?

        init(
            text: Binding<String>,
            selectedRange: Binding<NSRange>,
            focusModeEnabled: Bool,
            typewriterModeEnabled: Bool,
            autoPairEnabled: Bool,
            onVisibleSourceLineChange: @escaping (Int) -> Void
        ) {
            self.text = text
            self.selectedRange = selectedRange
            self.focusModeEnabled = focusModeEnabled
            self.typewriterModeEnabled = typewriterModeEnabled
            self.autoPairEnabled = autoPairEnabled
            self.onVisibleSourceLineChange = onVisibleSourceLineChange
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard autoPairEnabled, let replacementString, replacementString.count == 1 else {
                return true
            }

            let pairs = [
                "(": ")",
                "[": "]",
                "{": "}",
                "\"": "\"",
                "'": "'",
                "`": "`",
                "*": "*",
                "_": "_",
            ]

            let nsString = textView.string as NSString
            if
                pairs.values.contains(replacementString),
                affectedCharRange.length == 0,
                affectedCharRange.location < nsString.length,
                nsString.substring(with: NSRange(location: affectedCharRange.location, length: 1)) == replacementString
            {
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                syncSelection(from: textView)
                return false
            }

            guard let closing = pairs[replacementString] else {
                return true
            }

            let selectedText = affectedCharRange.length > 0 ? nsString.substring(with: affectedCharRange) : ""
            let insertedText = replacementString + selectedText + closing
            guard textView.shouldChangeText(in: affectedCharRange, replacementString: insertedText) else {
                return false
            }

            textView.textStorage?.replaceCharacters(in: affectedCharRange, with: insertedText)
            let nextSelection = selectedText.isEmpty
                ? NSRange(location: affectedCharRange.location + 1, length: 0)
                : NSRange(location: affectedCharRange.location + 1, length: (selectedText as NSString).length)
            textView.setSelectedRange(nextSelection)
            textView.didChangeText()
            syncSelection(from: textView)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate, !isApplyingSyntaxHighlighting else {
                return
            }
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
            if !textView.hasMarkedText() {
                syncSelection(from: textView)
                applySyntaxHighlighting(to: textView)
            }
            refreshLineNumbers(for: textView)
            publishVisibleSourceLine()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate, !isApplyingSyntaxHighlighting else {
                return
            }
            guard let textView = notification.object as? NSTextView else {
                return
            }
            guard !textView.hasMarkedText() else {
                return
            }
            syncSelection(from: textView)
            if focusModeEnabled {
                applySyntaxHighlighting(to: textView)
            }
            if typewriterModeEnabled {
                centerCurrentSelection(in: textView)
            }
        }

        func syncSelection(from textView: NSTextView) {
            let textLength = (textView.string as NSString).length
            guard let range = textView.selectedRange().clamped(toLength: textLength) else {
                return
            }
            lastSelectionPublishedToSwiftUI = range
            guard selectedRange.wrappedValue != range else {
                return
            }
            selectedRange.wrappedValue = range
        }

        func shouldApplySelectionFromBinding(_ range: NSRange, to textView: NSTextView) -> Bool {
            guard textView.selectedRange() != range else {
                lastSelectionPublishedToSwiftUI = range
                return false
            }

            return lastSelectionPublishedToSwiftUI != range
        }

        func rememberSelectionAppliedFromBinding(_ range: NSRange) {
            lastSelectionPublishedToSwiftUI = range
        }

        func applySyntaxHighlighting(to textView: NSTextView) {
            guard !isApplyingSyntaxHighlighting, !textView.hasMarkedText() else {
                return
            }

            let currentText = textView.string
            let currentFocusRange = focusModeEnabled ? textView.selectedRange() : nil
            guard
                currentText != lastHighlightedText ||
                currentFocusRange != lastHighlightedFocusRange
            else {
                return
            }

            isApplyingSyntaxHighlighting = true
            MarkdownSyntaxHighlighter.apply(
                to: textView,
                focusRange: currentFocusRange
            )
            lastHighlightedText = currentText
            lastHighlightedFocusRange = currentFocusRange
            isApplyingSyntaxHighlighting = false
        }

        func shouldApplyScrollTarget(_ target: SourceLineScrollTarget) -> Bool {
            lastAppliedScrollTarget != target
        }

        func applyScrollTarget(_ target: SourceLineScrollTarget) {
            guard let textView else {
                return
            }

            pendingScrollReapply?.cancel()
            lastAppliedScrollTarget = target
            isApplyingScrollTarget = true
            scrollSourceLineToTop(target, in: textView)
            refreshLineNumbers(for: textView)

            DispatchQueue.main.async { [weak self] in
                self?.reapplyScrollTargetIfCurrent(target)
            }

            let reapplyWork = DispatchWorkItem { [weak self] in
                self?.reapplyScrollTargetIfCurrent(target)
                self?.isApplyingScrollTarget = false
            }
            pendingScrollReapply = reapplyWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: reapplyWork)
        }

        private func reapplyScrollTargetIfCurrent(_ target: SourceLineScrollTarget) {
            guard lastAppliedScrollTarget == target, let textView else {
                return
            }
            scrollSourceLineToTop(target, in: textView)
            refreshLineNumbers(for: textView)
        }

        func publishVisibleSourceLine() {
            guard !isApplyingScrollTarget, let textView else {
                return
            }

            let line = visibleSourceLine(in: textView)
            guard line != lastPublishedVisibleSourceLine else {
                return
            }

            lastPublishedVisibleSourceLine = line
            DispatchQueue.main.async { [weak self] in
                self?.onVisibleSourceLineChange(line)
            }
        }

        private func centerCurrentSelection(in textView: NSTextView) {
            guard
                let scrollView = textView.enclosingScrollView,
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: textView.selectedRange(),
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let targetY = max(0, rect.midY - scrollView.contentView.bounds.height / 2)
            scroll(toY: targetY, in: scrollView)
        }

        private func scrollSourceLineToTop(_ target: SourceLineScrollTarget, in textView: NSTextView) {
            guard
                let scrollView = textView.enclosingScrollView,
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let characterRange = sourceRange(for: target, in: textView.string)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let targetY = lineRect.minY + textView.textContainerOrigin.y - textView.textContainerInset.height - 12
            scroll(toY: targetY, in: scrollView)
        }

        private func sourceRange(for target: SourceLineScrollTarget, in text: String) -> NSRange {
            let nsString = text as NSString
            if
                let location = target.location,
                location >= 0,
                location <= nsString.length
            {
                return nsString.lineRange(for: NSRange(location: location, length: 0))
            }

            return sourceRange(forLine: target.line, in: text)
        }

        private func scroll(toY targetY: CGFloat, in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else {
                return
            }

            let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            let clampedY = min(max(0, targetY), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func refreshLineNumbers(for textView: NSTextView) {
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        private func visibleSourceLine(in textView: NSTextView) -> Int {
            guard let scrollView = textView.enclosingScrollView else {
                return 1
            }

            let visibleRect = scrollView.contentView.bounds
            let point = NSPoint(
                x: max(textView.textContainerInset.width + 2, visibleRect.minX + 2),
                y: visibleRect.minY + textView.textContainerInset.height + 2
            )
            let characterIndex = textView.characterIndexForInsertion(at: point)
            return sourceLineNumber(at: characterIndex, in: textView.string)
        }

        private func sourceRange(forLine line: Int, in text: String) -> NSRange {
            let targetLine = max(1, line)
            let nsString = text as NSString
            guard nsString.length > 0, targetLine > 1 else {
                return nsString.lineRange(for: NSRange(location: 0, length: 0))
            }

            var currentLine = 1
            for index in 0..<nsString.length {
                guard nsString.character(at: index) == 10 else {
                    continue
                }

                currentLine += 1
                if currentLine == targetLine {
                    return nsString.lineRange(for: NSRange(location: min(index + 1, nsString.length), length: 0))
                }
            }

            return nsString.lineRange(for: NSRange(location: nsString.length, length: 0))
        }

        private func sourceLineNumber(at characterIndex: Int, in text: String) -> Int {
            let nsString = text as NSString
            let upperBound = min(max(0, characterIndex), nsString.length)
            guard upperBound > 0 else {
                return 1
            }

            var line = 1
            for index in 0..<upperBound where nsString.character(at: index) == 10 {
                line += 1
            }
            return line
        }
    }

    private func configureLineNumbers(for scrollView: NSScrollView, textView: NSTextView, enabled: Bool) {
        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false
        scrollView.verticalRulerView = nil

        if let markdownTextView = textView as? MarkdownTextView {
            markdownTextView.lineNumbersEnabled = enabled
        }

        guard let markdownScrollView = scrollView as? MarkdownEditorScrollView else {
            return
        }

        if enabled {
            if markdownScrollView.lineNumberGutterView == nil {
                let gutterView = LineNumberGutterView(textView: textView)
                markdownScrollView.lineNumberGutterView = gutterView
                scrollView.addSubview(gutterView, positioned: .above, relativeTo: scrollView.contentView)
            }
            markdownScrollView.lineNumberGutterView?.isHidden = false
            markdownScrollView.lineNumberGutterView?.needsDisplay = true
        } else {
            markdownScrollView.lineNumberGutterView?.isHidden = true
        }
    }

    static func updateTextContainerGeometry(for scrollView: NSScrollView, textView: NSTextView) {
        let contentWidth = max(scrollView.contentSize.width, 240)
        var frame = textView.frame
        var didChangeFrame = false

        if abs(frame.width - contentWidth) > 0.5 {
            frame.size.width = contentWidth
            didChangeFrame = true
        }

        textView.textContainer?.containerSize = NSSize(
            width: contentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)

        if
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        {
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let targetHeight = max(
                scrollView.contentSize.height,
                ceil(usedHeight + textView.textContainerInset.height * 2 + 4)
            )

            if abs(frame.height - targetHeight) > 0.5 {
                frame.size.height = targetHeight
                didChangeFrame = true
            }
        }

        if didChangeFrame {
            textView.frame = frame
        }

        clampScrollPosition(in: scrollView)
    }

    private static func clampScrollPosition(in scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else {
            return
        }

        let visibleBounds = scrollView.contentView.bounds
        let maxY = max(0, documentView.bounds.height - visibleBounds.height)
        guard visibleBounds.origin.y > maxY + 0.5 else {
            return
        }

        let markdownScrollView = scrollView as? MarkdownEditorScrollView
        markdownScrollView?.suppressVisibleBoundsChange = true
        scrollView.contentView.scroll(to: NSPoint(x: visibleBounds.origin.x, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        markdownScrollView?.suppressVisibleBoundsChange = false
    }
}

private final class MarkdownEditorScrollView: NSScrollView {
    weak var lineNumberGutterView: LineNumberGutterView?
    var onVisibleBoundsChange: (() -> Void)?
    var suppressVisibleBoundsChange = false

    override func layout() {
        super.layout()
        lineNumberGutterView?.frame = NSRect(
            x: contentView.frame.minX,
            y: contentView.frame.minY,
            width: 44,
            height: contentView.frame.height
        )
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        lineNumberGutterView?.needsDisplay = true
        if !suppressVisibleBoundsChange {
            onVisibleBoundsChange?()
        }
    }
}

private final class MarkdownTextView: NSTextView {
    var insertImageURLs: (([URL]) -> Void)?
    var pasteImage: ((NSPasteboard) -> Bool)?
    var lineNumbersEnabled = false {
        didSet {
            guard lineNumbersEnabled != oldValue else {
                return
            }
            textContainerInset = NSSize(width: lineNumbersEnabled ? 56 : 18, height: 18)
            needsDisplay = true
        }
    }
    private var didRequestInitialFocus = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didRequestInitialFocus, window != nil else {
            return
        }

        didRequestInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if imageURLs(from: sender.draggingPasteboard).isEmpty {
            return super.draggingEntered(sender)
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else {
            return super.performDragOperation(sender)
        }
        insertImageURLs?(urls)
        return true
    }

    override func paste(_ sender: Any?) {
        if pasteImage?(NSPasteboard.general) == true {
            return
        }
        super.paste(sender)
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]

        return (urls ?? []).filter { url in
            ["png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "svg"]
                .contains(url.pathExtension.lowercased())
        }
    }

}

private final class LineNumberGutterView: NSView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        autoresizingMask = [.height]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            let scrollView = textView.enclosingScrollView
        else {
            return
        }

        let visibleRect = scrollView.contentView.bounds
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        layoutManager.ensureLayout(for: textContainer)

        let string = textView.string as NSString
        if string.length == 0 {
            drawLineNumber(1, atY: textView.textContainerOrigin.y - visibleRect.minY)
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location != NSNotFound else {
            return
        }

        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let fullRange = NSRange(location: 0, length: string.length)
        var lineNumber = 1

        string.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            defer { lineNumber += 1 }

            guard NSIntersectionRange(enclosingRange, visibleCharacterRange).length > 0 else {
                return
            }

            let characterIndex = min(lineRange.location, max(0, string.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            self.drawLineNumber(lineNumber, atY: lineRect.minY + textView.textContainerOrigin.y - visibleRect.minY)
        }
    }

    private func drawLineNumber(_ lineNumber: Int, atY y: CGFloat) {
        let label = "\(lineNumber)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        label.draw(
            in: NSRect(x: 6, y: y, width: 34, height: 14),
            withAttributes: attributes
        )
    }
}

extension NSRange {
    func clamped(toLength length: Int) -> NSRange? {
        guard location <= length else {
            return nil
        }

        let upperBound = Swift.min(location + self.length, length)
        return NSRange(location: location, length: upperBound - location)
    }
}

extension Array where Element == NSValue {
    func clampedSelectionRanges(toLength length: Int, fallback: NSRange? = nil) -> [NSValue] {
        let clampedRanges = compactMap { value -> NSValue? in
            guard let range = value.rangeValue.clamped(toLength: length) else {
                return nil
            }
            return NSValue(range: range)
        }

        if !clampedRanges.isEmpty {
            return clampedRanges
        }

        let fallbackRange = fallback?.clamped(toLength: length) ?? NSRange(location: length, length: 0)
        return [NSValue(range: fallbackRange)]
    }
}
