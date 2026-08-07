import SwiftUI
import AppKit

/// Plain-text markdown editor. Adapted from Stickies' `NoteTextEditor`, with
/// rich text swapped out for plain text plus syntax dimming.
///
/// The text view owns the in-flight buffer; changes are reported by callback
/// rather than through a `Binding`, which would fight the text view mid-keystroke.
/// External replacements (opening a file, reloading from disk) arrive as a
/// bumped `revision`.
struct EditorView: NSViewRepresentable {
    let text: String
    /// Changes whenever the store replaces the buffer from outside the editor.
    let revision: Int
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.scrollerStyle = .overlay

        // Build the TextKit 1 stack explicitly. Temporary attributes - how the
        // syntax dimming is applied without touching the text storage or the
        // undo stack - live on the layout manager, which TextKit 2 does not
        // vend.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0

        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = Theme.nsText
        textView.insertionPointColor = Theme.nsText
        textView.font = Theme.font()
        textView.textContainerInset = .zero
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.typingAttributes = Self.typingAttributes()
        textView.delegate = context.coordinator

        textView.string = text
        textView.textStorage?.addAttributes(
            Self.typingAttributes(),
            range: NSRange(location: 0, length: (text as NSString).length)
        )

        context.coordinator.textView = textView
        context.coordinator.revision = revision
        context.coordinator.applyDimming()

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }

        // Only replace the contents when the store says this is a different
        // buffer, never on every keystroke.
        if context.coordinator.revision != revision {
            context.coordinator.revision = revision
            if textView.string != text {
                textView.string = text
                textView.textStorage?.addAttributes(
                    Self.typingAttributes(),
                    range: NSRange(location: 0, length: (text as NSString).length)
                )
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            context.coordinator.applyDimming()
        }

        // Keep the text view pinned to the clip view's width so long lines
        // wrap instead of overflowing horizontally.
        let targetWidth = scroll.contentView.bounds.width
        guard targetWidth > 0, textView.frame.width != targetWidth else { return }
        textView.setFrameSize(NSSize(width: targetWidth, height: textView.frame.height))
        textView.textContainer?.containerSize =
            NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    static func typingAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Theme.lineHeightMultiple
        return [
            .font: Theme.font(),
            .foregroundColor: Theme.nsText,
            .paragraphStyle: paragraph,
            .kern: Theme.tracking,
            // Geist Mono collapses `...` into a narrower ellipsis ligature that
            // visually overlaps prior glyphs, so ligatures stay off.
            .ligature: 0,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onChange: (String) -> Void
        weak var textView: NSTextView?
        var revision = -1

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            applyDimming()
            onChange(textView.string)
        }

        /// Fades markdown syntax characters so they recede while writing.
        ///
        /// Uses temporary attributes: they are a display-layer overlay, so the
        /// text storage, the undo stack, and what gets written to disk are all
        /// untouched.
        func applyDimming() {
            guard let textView, let layout = textView.layoutManager else { return }
            let text = textView.string as NSString
            let full = NSRange(location: 0, length: text.length)

            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            for range in SyntaxRanges.find(in: textView.string) {
                layout.addTemporaryAttributes([.foregroundColor: Theme.nsSyntax],
                                              forCharacterRange: range)
            }
        }
    }
}

/// Locates the markdown syntax characters that should recede while editing.
enum SyntaxRanges {
    private static let patterns: [String] = [
        "(?m)^\\s{0,3}#{1,6}\\s",      // heading hashes
        "(?m)^\\s*[-*+]\\s",           // bullet markers
        "(?m)^\\s*\\d+\\.\\s",         // ordered markers
        "(?m)^\\s*>\\s?",              // quote markers
        "(?m)^\\s*(```|~~~).*$",       // fence lines, language tag included
        "\\*\\*",                      // bold delimiters
        "`",                           // code delimiters
    ]

    private static let expressions: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0)
    }

    static func find(in text: String) -> [NSRange] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        return expressions.flatMap { expression in
            expression.matches(in: text, range: full).map(\.range)
        }
    }
}
