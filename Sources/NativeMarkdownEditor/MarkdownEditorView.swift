import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    private static let minimumTextContainerWidth: CGFloat = 120
    private static let overlayScrollerReservedWidth: CGFloat = 18
    static let visibleBoundsPublishDelay: TimeInterval = 0.03

    @Binding var text: String
    @Binding var selectedRange: NSRange
    let contentRevision: Int
    let focusModeEnabled: Bool
    let typewriterModeEnabled: Bool
    let lineNumbersEnabled: Bool
    let autoPairEnabled: Bool
    let scrollTarget: SourceLineScrollTarget?
    let onTextEdit: (SourceLineIndexEdit, NSRange, () -> String) -> Void
    let onVisibleSourceLineChange: (Int) -> Void
    let onInsertImageURLs: ([URL]) -> Void
    let onPasteImage: (NSPasteboard) -> Bool

    static func configureLargeTextLayout(for textView: NSTextView) {
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedRange: $selectedRange,
            contentRevision: contentRevision,
            focusModeEnabled: focusModeEnabled,
            typewriterModeEnabled: typewriterModeEnabled,
            autoPairEnabled: autoPairEnabled,
            onTextEdit: onTextEdit,
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
        context.coordinator.rebuildLineIndex(for: textView)
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
        Self.configureLargeTextLayout(for: textView)
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
            width: Self.textContainerWidth(for: initialTextWidth, textView: textView),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        let coordinator = context.coordinator
        scrollView.onVisibleBoundsChange = { [weak coordinator] in
            coordinator?.scheduleVisibleSourceLinePublish()
        }
        coordinator.observeVisibleBoundsChanges(in: scrollView)
        coordinator.textView = textView
        configureLineNumbers(for: scrollView, textView: textView, enabled: lineNumbersEnabled)
        coordinator.applySyntaxHighlighting(to: textView)
        Self.updateTextContainerGeometry(for: scrollView, textView: textView, recalculateHeight: true)
        coordinator.rememberGeometryUpdate(for: scrollView, textView: textView)
        DispatchQueue.main.async { [weak scrollView, weak textView, weak coordinator] in
            guard let scrollView, let textView, let coordinator else {
                return
            }
            Self.updateTextContainerGeometry(for: scrollView, textView: textView, recalculateHeight: true)
            coordinator.rememberGeometryUpdate(for: scrollView, textView: textView)
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
        context.coordinator.onTextEdit = onTextEdit
        context.coordinator.onVisibleSourceLineChange = onVisibleSourceLineChange
        let pendingScrollTarget = scrollTarget.flatMap { target in
            context.coordinator.shouldApplyScrollTarget(target) ? target : nil
        }
        var shouldRecalculateHeight = context.coordinator.consumeGeometryRecalculation()

        if context.coordinator.shouldApplyTextBinding(contentRevision: contentRevision) {
            if context.coordinator.consumeDirectEditEchoIfMatching(
                text: text,
                textView: textView,
                contentRevision: contentRevision
            ) {
                // The NSTextView already contains this local edit; only SwiftUI's binding echo caught up.
            } else {
                guard !textView.hasMarkedText() else {
                    return
                }

                let selectedRanges = textView.selectedRanges
                let textLength = (text as NSString).length
                context.coordinator.isApplyingExternalUpdate = true
                textView.string = text
                context.coordinator.noteTextChanged()
                context.coordinator.rebuildLineIndex(for: textView)
                textView.selectedRanges = selectedRanges.clampedSelectionRanges(
                    toLength: textLength,
                    fallback: selectedRange
                )
                context.coordinator.markGeometryNeedsRecalculation()
                shouldRecalculateHeight = true
                context.coordinator.rememberTextBindingApplied(contentRevision: contentRevision)
                context.coordinator.isApplyingExternalUpdate = false
            }
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
        configureLineNumbers(for: scrollView, textView: textView, enabled: lineNumbersEnabled)
        if context.coordinator.needsGeometryUpdate(
            for: scrollView,
            textView: textView,
            recalculateHeight: shouldRecalculateHeight
        ) {
            Self.updateTextContainerGeometry(
                for: scrollView,
                textView: textView,
                recalculateHeight: shouldRecalculateHeight
            )
            context.coordinator.rememberGeometryUpdate(for: scrollView, textView: textView)
        }

        if let pendingScrollTarget {
            context.coordinator.applyScrollTarget(pendingScrollTarget)
        }
        context.coordinator.observeVisibleBoundsChanges(in: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingVisibleBoundsChanges()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var selectedRange: Binding<NSRange>
        weak var textView: NSTextView?
        var isApplyingExternalUpdate = false
        var focusModeEnabled: Bool
        var typewriterModeEnabled: Bool
        var autoPairEnabled: Bool
        var onTextEdit: (SourceLineIndexEdit, NSRange, () -> String) -> Void
        var onVisibleSourceLineChange: (Int) -> Void
        private var lastSelectionPublishedToSwiftUI: NSRange?
        private var isApplyingSyntaxHighlighting = false
        private var isApplyingScrollTarget = false
        private var lastAppliedScrollTarget: SourceLineScrollTarget?
        private var lastPublishedVisibleSourceLine: Int?
        private var textRevision = 0
        private var lastHighlightedTextRevision: Int?
        private var lastHighlightedFocusRange: NSRange?
        private var pendingScrollReapply: DispatchWorkItem?
        private var needsGeometryRecalculation = true
        private var sourceLineIndex = SourceLineIndex(text: "")
        private var pendingLineIndexEdit: SourceLineIndexEdit?
        private var lastGeometryContentSize: NSSize?
        private var lastGeometryTextContainerInset: NSSize?
        private var lastGeometryTextLength: Int?
        private var visibleBoundsObserver: NSObjectProtocol?
        private weak var observedScrollView: NSScrollView?
        private var pendingVisibleBoundsPublish: DispatchWorkItem?
        private var pendingDirectEditEchoTextLength: Int?
        private var pendingDirectEditEchoContentRevision: Int?
        private var lastAppliedContentRevision: Int

        init(
            text: Binding<String>,
            selectedRange: Binding<NSRange>,
            contentRevision: Int,
            focusModeEnabled: Bool,
            typewriterModeEnabled: Bool,
            autoPairEnabled: Bool,
            onTextEdit: @escaping (SourceLineIndexEdit, NSRange, () -> String) -> Void,
            onVisibleSourceLineChange: @escaping (Int) -> Void
        ) {
            self.text = text
            self.selectedRange = selectedRange
            lastAppliedContentRevision = contentRevision
            self.focusModeEnabled = focusModeEnabled
            self.typewriterModeEnabled = typewriterModeEnabled
            self.autoPairEnabled = autoPairEnabled
            self.onTextEdit = onTextEdit
            self.onVisibleSourceLineChange = onVisibleSourceLineChange
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            pendingLineIndexEdit = SourceLineIndexEdit(
                range: affectedCharRange,
                replacement: replacementString ?? ""
            )

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
                pendingLineIndexEdit = nil
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
                pendingLineIndexEdit = nil
                return false
            }

            pendingLineIndexEdit = SourceLineIndexEdit(
                range: affectedCharRange,
                replacement: insertedText
            )
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
            noteTextChanged()
            let directEdit = pendingLineIndexEdit
            updateLineIndexAfterTextChange(for: textView)
            if let directEdit {
                pendingDirectEditEchoTextLength = (textView.string as NSString).length
                pendingDirectEditEchoContentRevision = lastAppliedContentRevision + 1
                onTextEdit(directEdit, textView.selectedRange()) { [weak textView] in
                    textView?.string ?? ""
                }
            } else {
                text.wrappedValue = textView.string
            }
            markGeometryNeedsRecalculation()
            if !textView.hasMarkedText() {
                syncSelection(from: textView)
                applySyntaxHighlighting(to: textView)
            }
            refreshLineNumbers(for: textView)
            publishVisibleSourceLine()
        }

        func rebuildLineIndex(for textView: NSTextView) {
            pendingLineIndexEdit = nil
            sourceLineIndex = SourceLineIndex(text: textView.string)
            (textView as? MarkdownTextView)?.sourceLineIndex = sourceLineIndex
        }

        func updateLineIndexAfterTextChange(for textView: NSTextView) {
            let textLength = (textView.string as NSString).length
            if
                let pendingLineIndexEdit,
                let updatedLineIndex = sourceLineIndex.updating(
                    with: pendingLineIndexEdit,
                    newTextLength: textLength
                )
            {
                sourceLineIndex = updatedLineIndex
                (textView as? MarkdownTextView)?.sourceLineIndex = updatedLineIndex
            } else {
                rebuildLineIndex(for: textView)
            }
            pendingLineIndexEdit = nil
        }

        func shouldApplyTextBinding(contentRevision: Int) -> Bool {
            contentRevision != lastAppliedContentRevision
        }

        func rememberTextBindingApplied(contentRevision: Int) {
            lastAppliedContentRevision = contentRevision
            pendingDirectEditEchoTextLength = nil
            pendingDirectEditEchoContentRevision = nil
        }

        func consumeDirectEditEchoIfMatching(
            text: String,
            textView: NSTextView,
            contentRevision: Int
        ) -> Bool {
            guard
                let pendingDirectEditEchoTextLength,
                pendingDirectEditEchoContentRevision == contentRevision
            else {
                return false
            }

            let bindingLength = (text as NSString).length
            let textViewLength = (textView.string as NSString).length
            guard bindingLength == pendingDirectEditEchoTextLength,
                  textViewLength == pendingDirectEditEchoTextLength else {
                return false
            }

            self.pendingDirectEditEchoTextLength = nil
            pendingDirectEditEchoContentRevision = nil
            lastAppliedContentRevision = contentRevision
            return true
        }

        func noteTextChanged() {
            textRevision += 1
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

        func markGeometryNeedsRecalculation() {
            needsGeometryRecalculation = true
        }

        func consumeGeometryRecalculation() -> Bool {
            let value = needsGeometryRecalculation
            needsGeometryRecalculation = false
            return value
        }

        func needsGeometryUpdate(
            for scrollView: NSScrollView,
            textView: NSTextView,
            recalculateHeight: Bool
        ) -> Bool {
            if recalculateHeight {
                return true
            }

            guard
                let lastGeometryContentSize,
                let lastGeometryTextContainerInset,
                let lastGeometryTextLength
            else {
                return true
            }

            let textLength = (textView.string as NSString).length
            return !Self.isSameSize(lastGeometryContentSize, scrollView.contentSize) ||
                !Self.isSameSize(lastGeometryTextContainerInset, textView.textContainerInset) ||
                lastGeometryTextLength != textLength
        }

        func rememberGeometryUpdate(for scrollView: NSScrollView, textView: NSTextView) {
            lastGeometryContentSize = scrollView.contentSize
            lastGeometryTextContainerInset = textView.textContainerInset
            lastGeometryTextLength = (textView.string as NSString).length
        }

        private static func isSameSize(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
            abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
        }

        func applySyntaxHighlighting(to textView: NSTextView) {
            guard !isApplyingSyntaxHighlighting, !textView.hasMarkedText() else {
                return
            }

            let characterCount = (textView.string as NSString).length
            let canApplyFocusStyle = MarkdownSyntaxHighlighter.usesFullHighlighting(characterCount: characterCount)
            let currentFocusRange = focusModeEnabled && canApplyFocusStyle ? textView.selectedRange() : nil
            guard
                lastHighlightedTextRevision != textRevision ||
                currentFocusRange != lastHighlightedFocusRange
            else {
                return
            }

            isApplyingSyntaxHighlighting = true
            MarkdownSyntaxHighlighter.apply(
                to: textView,
                focusRange: currentFocusRange
            )
            lastHighlightedTextRevision = textRevision
            lastHighlightedFocusRange = currentFocusRange
            isApplyingSyntaxHighlighting = false
        }

        func shouldApplyScrollTarget(_ target: SourceLineScrollTarget) -> Bool {
            lastAppliedScrollTarget != target
        }

        func observeVisibleBoundsChanges(in scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else {
                return
            }

            stopObservingVisibleBoundsChanges()
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            visibleBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleVisibleSourceLinePublish()
            }
        }

        func stopObservingVisibleBoundsChanges() {
            pendingVisibleBoundsPublish?.cancel()
            pendingVisibleBoundsPublish = nil
            if let visibleBoundsObserver {
                NotificationCenter.default.removeObserver(visibleBoundsObserver)
            }
            visibleBoundsObserver = nil
            observedScrollView = nil
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

            let line = MarkdownEditorView.visibleSourceLine(in: textView, sourceLineIndex: sourceLineIndex)
            guard line != lastPublishedVisibleSourceLine else {
                return
            }

            lastPublishedVisibleSourceLine = line
            DispatchQueue.main.async { [weak self] in
                self?.onVisibleSourceLineChange(line)
            }
        }

        func scheduleVisibleSourceLinePublish() {
            guard !isApplyingScrollTarget else {
                return
            }

            pendingVisibleBoundsPublish?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.publishVisibleSourceLine()
            }
            pendingVisibleBoundsPublish = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + MarkdownEditorView.visibleBoundsPublishDelay,
                execute: work
            )
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

        private func sourceRange(forLine line: Int, in text: String) -> NSRange {
            let nsString = text as NSString
            guard nsString.length > 0 else {
                return nsString.lineRange(for: NSRange(location: 0, length: 0))
            }

            let indexedRange = sourceLineIndex.range(forLine: line)
            guard indexedRange.location <= nsString.length else {
                return nsString.lineRange(for: NSRange(location: nsString.length, length: 0))
            }
            return nsString.lineRange(for: NSRange(location: indexedRange.location, length: 0))
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

    static func updateTextContainerGeometry(
        for scrollView: NSScrollView,
        textView: NSTextView,
        recalculateHeight: Bool = true
    ) {
        let contentWidth = max(scrollView.contentSize.width, 240)
        let textContainerWidth = Self.textContainerWidth(for: contentWidth, textView: textView)
        var frame = textView.frame
        var didChangeFrame = false
        var didChangeWidth = false

        if abs(frame.width - contentWidth) > 0.5 {
            frame.size.width = contentWidth
            didChangeFrame = true
            didChangeWidth = true
        }

        if didChangeFrame {
            textView.frame = frame
            didChangeFrame = false
        }

        if let textContainer = textView.textContainer {
            let currentContainerSize = textContainer.containerSize
            if abs(currentContainerSize.width - textContainerWidth) > 0.5 {
                didChangeWidth = true
            }
            if textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = false
            }
            if
                didChangeWidth ||
                currentContainerSize.height != CGFloat.greatestFiniteMagnitude
            {
                textContainer.containerSize = NSSize(
                    width: textContainerWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
        }
        if abs(textView.minSize.height - scrollView.contentSize.height) > 0.5 {
            textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        }

        if recalculateHeight || didChangeWidth {
            let targetHeight = PerformanceDiagnostics.shared.measure(
                "editor.geometry",
                metadata: [
                    "characters": "\((textView.string as NSString).length)",
                    "recalculate": recalculateHeight ? "true" : "false",
                    "width_changed": didChangeWidth ? "true" : "false",
                ]
            ) {
                targetDocumentHeight(
                    for: scrollView,
                    textView: textView,
                    textContainerWidth: textContainerWidth
                )
            }

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

    static func visibleSourceLine(in textView: NSTextView, sourceLineIndex: SourceLineIndex) -> Int {
        guard let scrollView = textView.enclosingScrollView else {
            return 1
        }

        let visibleRect = scrollView.contentView.bounds
        let pointInTextView = NSPoint(
            x: max(textView.textContainerInset.width + 2, visibleRect.minX + 2),
            y: visibleRect.minY + textView.textContainerInset.height + 2
        )

        if
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        {
            let containerOrigin = textView.textContainerOrigin
            let pointInContainer = NSPoint(
                x: max(0, pointInTextView.x - containerOrigin.x),
                y: max(0, pointInTextView.y - containerOrigin.y)
            )
            let visibleContainerRect = NSRect(
                x: 0,
                y: max(0, visibleRect.minY - containerOrigin.y),
                width: max(textContainer.containerSize.width, visibleRect.width),
                height: max(1, visibleRect.height)
            )
            layoutManager.ensureLayout(forBoundingRect: visibleContainerRect, in: textContainer)

            let glyphCount = layoutManager.numberOfGlyphs
            if glyphCount > 0 {
                let visibleGlyphRange = layoutManager.glyphRange(
                    forBoundingRect: visibleContainerRect,
                    in: textContainer
                )
                if visibleGlyphRange.location != NSNotFound, visibleGlyphRange.length > 0 {
                    let characterIndex = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)
                    return sourceLineIndex.lineNumber(at: characterIndex)
                }

                let glyphIndex = min(
                    layoutManager.glyphIndex(for: pointInContainer, in: textContainer),
                    glyphCount - 1
                )
                let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                return sourceLineIndex.lineNumber(at: characterIndex)
            }
        }

        let fallbackCharacterIndex = textView.characterIndexForInsertion(at: pointInTextView)
        return sourceLineIndex.lineNumber(at: fallbackCharacterIndex)
    }

    private static func textContainerWidth(for contentWidth: CGFloat, textView: NSTextView) -> CGFloat {
        let lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        let reservedHorizontalSpace =
            textView.textContainerInset.width * 2 +
            lineFragmentPadding * 2 +
            overlayScrollerReservedWidth

        return max(minimumTextContainerWidth, contentWidth - reservedHorizontalSpace)
    }

    private static func targetDocumentHeight(
        for scrollView: NSScrollView,
        textView: NSTextView,
        textContainerWidth: CGFloat
    ) -> CGFloat {
        let characterCount = (textView.string as NSString).length
        let exactLayoutCharacterLimit = 250_000

        if
            characterCount <= exactLayoutCharacterLimit,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        {
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            return max(
                scrollView.contentSize.height,
                ceil(usedHeight + textView.textContainerInset.height * 2 + 4)
            )
        }

        return max(
            scrollView.contentSize.height,
            estimatedDocumentHeight(for: textView, textContainerWidth: textContainerWidth)
        )
    }

    private static func estimatedDocumentHeight(for textView: NSTextView, textContainerWidth: CGFloat) -> CGFloat {
        let sourceLineIndex = (textView as? MarkdownTextView)?.sourceLineIndex ?? SourceLineIndex(text: textView.string)
        let usableWidth = max(80, textContainerWidth)
        let font = textView.font ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
        let averageCharacterWidth = max(6, "m".size(withAttributes: [.font: font]).width)
        let charactersPerVisualLine = max(24, Int(floor(usableWidth / averageCharacterWidth)))
        let paragraphStyle = MarkdownSyntaxHighlighter.paragraphStyleForEditor()
        let lineHeight = ceil(font.ascender - font.descender + font.leading + paragraphStyle.lineSpacing)
        let visualLineCount = sourceLineIndex.estimatedVisualLineCount(
            charactersPerVisualLine: charactersPerVisualLine
        )

        return ceil(CGFloat(visualLineCount) * lineHeight + textView.textContainerInset.height * 2 + 12)
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
    var sourceLineIndex = SourceLineIndex(text: "")
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

        let containerOrigin = textView.textContainerOrigin
        let visibleContainerRect = NSRect(
            x: 0,
            y: max(0, visibleRect.minY - containerOrigin.y),
            width: max(textContainer.containerSize.width, visibleRect.width),
            height: max(1, visibleRect.height)
        )
        layoutManager.ensureLayout(forBoundingRect: visibleContainerRect, in: textContainer)

        let string = textView.string as NSString
        if string.length == 0 {
            drawLineNumber(1, atY: textView.textContainerOrigin.y - visibleRect.minY)
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleContainerRect, in: textContainer)
        guard glyphRange.location != NSNotFound else {
            return
        }

        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let sourceLineIndex = (textView as? MarkdownTextView)?.sourceLineIndex ?? SourceLineIndex(text: textView.string)
        let firstLine = max(1, sourceLineIndex.lineNumber(at: visibleCharacterRange.location) - 1)
        let lastLine = min(
            sourceLineIndex.lineCount,
            sourceLineIndex.lineNumber(at: NSMaxRange(visibleCharacterRange)) + 1
        )
        guard firstLine <= lastLine else {
            return
        }

        for lineNumber in firstLine...lastLine {
            let lineRange = sourceLineIndex.range(forLine: lineNumber)
            guard NSIntersectionRange(lineRange, visibleCharacterRange).length > 0 else {
                continue
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
