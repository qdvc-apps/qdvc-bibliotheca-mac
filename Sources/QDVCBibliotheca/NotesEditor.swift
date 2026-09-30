import AppKit
import SwiftUI

/// The notes editor: a plain-text `NSTextView` (native undo, spelling, Find,
/// services, dictation) with the same lightweight Markdown highlighting as the
/// GTK app. The text stays plain; only colours and font traits change.
struct NotesEditor: NSViewRepresentable {
    var text: String
    /// Changes when a different record's notes are shown; resets undo.
    var documentID: String?
    var fontSize: CGFloat
    var onEdit: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isContinuousSpellCheckingEnabled = true
            textView.textContainerInset = NSSize(width: 4, height: 6)
            context.coordinator.textView = textView
            context.coordinator.show(text, documentID: documentID, fontSize: fontSize)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if coordinator.documentID != documentID || textView.string != text {
            coordinator.show(text, documentID: documentID, fontSize: fontSize)
        } else if coordinator.fontSize != fontSize {
            coordinator.fontSize = fontSize
            coordinator.highlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor
        weak var textView: NSTextView?
        var documentID: String?
        var fontSize: CGFloat = 13
        private let highlighter = MarkdownHighlighter()

        init(_ parent: NotesEditor) {
            self.parent = parent
        }

        func show(_ text: String, documentID: String?, fontSize: CGFloat) {
            guard let textView else { return }
            let switchedDocument = documentID != self.documentID
            self.documentID = documentID
            self.fontSize = fontSize
            textView.string = text
            highlight()
            if switchedDocument {
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            }
            textView.isEditable = documentID != nil
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }
            let base = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            highlighter.apply(to: storage, baseFont: base)
            textView.typingAttributes = [.font: base, .foregroundColor: NSColor.textColor]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if !textView.hasMarkedText() { highlight() }
            parent.onEdit(textView.string)
        }
    }
}

/// Regex-based, line-oriented Markdown highlighting — a port of
/// `gtk4/gtk4_md_highlight.py`, using adaptive system colours so it reads well
/// in both light and dark mode.
final class MarkdownHighlighter {
    private let heading = MarkdownHighlighter.rx("^(#{1,6})\\s.*$")
    private let blockquote = MarkdownHighlighter.rx("^\\s*>.*$")
    private let listMarker = MarkdownHighlighter.rx("^\\s*([-*+]|\\d+\\.)\\s")
    private let rule = MarkdownHighlighter.rx("^\\s*([-*_])(\\s*\\1){2,}\\s*$")
    private let codeInline = MarkdownHighlighter.rx("`[^`\\n]+`")
    private let bold = MarkdownHighlighter.rx("(\\*\\*|__)(?=\\S)(.+?\\S)\\1")
    private let italic = MarkdownHighlighter.rx(
        "(?<!\\*)\\*(?!\\*)([^*\\n]+?)\\*(?!\\*)|(?<![\\w])_(?!_)([^_\\n]+?)_(?![\\w])")
    private let link = MarkdownHighlighter.rx("\\[[^\\]]+\\]\\([^)]+\\)")

    private static func rx(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            fatalError("Invalid highlighter pattern \(pattern): \(error)")
        }
    }

    func apply(to storage: NSTextStorage, baseFont: NSFont) {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.textColor], range: full)

        var inFence = false
        var location = 0
        while location < ns.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: location, length: 0))
            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = ns.substring(with: lineRange)
            let lineLength = (line as NSString).length
            let local = NSRange(location: 0, length: lineLength)

            func add(_ attrs: [NSAttributedString.Key: Any], _ r: NSRange) {
                guard r.location != NSNotFound, r.length > 0 else { return }
                storage.addAttributes(attrs, range: NSRange(location: lineStart + r.location, length: r.length))
            }
            func addTrait(_ trait: NSFontTraitMask, _ r: NSRange) {
                guard r.location != NSNotFound, r.length > 0 else { return }
                let target = NSRange(location: lineStart + r.location, length: r.length)
                storage.enumerateAttribute(.font, in: target) { value, subrange, _ in
                    let font = (value as? NSFont) ?? baseFont
                    let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
                    storage.addAttribute(.font, value: converted, range: subrange)
                }
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                add([.foregroundColor: NSColor.systemGreen], local)
            } else if inFence {
                add([.foregroundColor: NSColor.systemGreen], local)
            } else {
                if let m = heading.firstMatch(in: line, range: local) {
                    let level = min(m.range(at: 1).length, 6)
                    let colour = NSColor.systemBlue.withAlphaComponent(1.0 - CGFloat(level - 1) * 0.1)
                    add([.foregroundColor: colour], m.range)
                    addTrait(.boldFontMask, m.range)
                }
                if let m = blockquote.firstMatch(in: line, range: local) {
                    add([.foregroundColor: NSColor.systemPurple], m.range)
                    addTrait(.italicFontMask, m.range)
                }
                if let m = listMarker.firstMatch(in: line, range: local) {
                    add([.foregroundColor: NSColor.systemRed], m.range)
                    addTrait(.boldFontMask, m.range)
                }
                if let m = rule.firstMatch(in: line, range: local) {
                    add([.foregroundColor: NSColor.secondaryLabelColor], m.range)
                }
                for m in codeInline.matches(in: line, range: local) {
                    add([.foregroundColor: NSColor.systemOrange,
                         .backgroundColor: NSColor.quaternaryLabelColor], m.range)
                }
                for m in bold.matches(in: line, range: local) {
                    addTrait(.boldFontMask, m.range)
                }
                for m in italic.matches(in: line, range: local) {
                    addTrait(.italicFontMask, m.range)
                }
                for m in link.matches(in: line, range: local) {
                    add([.foregroundColor: NSColor.linkColor,
                         .underlineStyle: NSUnderlineStyle.single.rawValue], m.range)
                }
            }
            // Advance past this line (lineEnd includes the terminator).
            location = max(lineEnd, location + 1)
        }
        storage.endEditing()
    }
}
