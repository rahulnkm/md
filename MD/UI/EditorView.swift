import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    /// Hands pasted or dropped images to the store, which puts them on disk
    /// and returns the markdown to insert. Nil means nothing was written.
    let onImages: ([NSImage]) -> String?
    /// Changes whenever the user asks to find inside this file.
    var findRequest: Int = 0
    /// Where to land when the buffer is (re)opened.
    var position: FilePosition = FilePosition()
    /// Reports scroll offset and cursor as they change.
    var onPositionChange: (CGFloat, Int) -> Void = { _, _ in }

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

        let textView = VibrantTextView(frame: .zero, textContainer: container)
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
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.font = Theme.font()
        textView.textContainerInset = .zero
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.typingAttributes = Self.typingAttributes()
        textView.delegate = context.coordinator
        // The system find bar: incremental highlighting, next/previous,
        // Escape to dismiss. It docks at the top of the scroll view.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.onImages = onImages
        // A plain-text view only registers for text drops. Image files and
        // raw image data have to be asked for.
        textView.registerForDraggedTypes(textView.registeredDraggedTypes + [.fileURL, .png, .tiff])

        textView.string = text
        textView.textStorage?.addAttributes(
            Self.typingAttributes(),
            range: NSRange(location: 0, length: (text as NSString).length)
        )

        context.coordinator.textView = textView
        context.coordinator.revision = revision
        context.coordinator.findRequest = findRequest
        context.coordinator.onPositionChange = onPositionChange
        context.coordinator.applyDimming()

        scroll.documentView = textView

        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.reportPosition()
        }
        context.coordinator.restore(position)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }

        context.coordinator.onPositionChange = onPositionChange

        // Only replace the contents when the store says this is a different
        // buffer, never on every keystroke.
        if context.coordinator.revision != revision {
            context.coordinator.revision = revision
            // Replacing the text scrolls to the top; that must not be
            // recorded as the user's position in the file being opened.
            context.coordinator.restoring = true
            if textView.string != text {
                textView.string = text
                textView.textStorage?.addAttributes(
                    Self.typingAttributes(),
                    range: NSRange(location: 0, length: (text as NSString).length)
                )
            }
            context.coordinator.applyDimming()
            context.coordinator.restore(position)
        }

        if context.coordinator.findRequest != findRequest {
            context.coordinator.findRequest = findRequest
            context.coordinator.showFindBar()
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
            .foregroundColor: NSColor.labelColor,
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
        var findRequest = 0
        var onPositionChange: (CGFloat, Int) -> Void = { _, _ in }
        var observer: NSObjectProtocol?
        /// True while a programmatic jump is in flight, so the scroll it
        /// causes is not recorded as the user's doing.
        var restoring = false

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            reportPosition()
        }

        func reportPosition() {
            guard !restoring, let textView, let scroll = textView.enclosingScrollView else { return }
            onPositionChange(scroll.contentView.bounds.origin.y, textView.selectedRange().location)
        }

        /// Puts the cursor and the scroll offset back. Layout is lazy, so it
        /// is forced first or a long file has no height to scroll into, and
        /// the jump waits a turn for the view to be in its window.
        func restore(_ position: FilePosition) {
            restoring = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                let length = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: min(position.cursor, length), length: 0))
                if let scroll = textView.enclosingScrollView {
                    if let container = textView.textContainer {
                        textView.layoutManager?.ensureLayout(for: container)
                    }
                    let maxY = max(0, textView.frame.height - scroll.contentView.bounds.height)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: min(position.editOffset, maxY)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                self.restoring = false
            }
        }

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            applyDimming()
            onChange(textView.string)
        }

        /// `performTextFinderAction` reads the action off its sender's tag,
        /// the way a menu item would carry it.
        func showFindBar(attempt: Int = 0) {
            guard let textView else { return }
            // No window yet means the view was just created; try again once
            // it has been mounted rather than acting on nothing.
            guard textView.window != nil else {
                if attempt < 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.showFindBar(attempt: attempt + 1)
                    }
                }
                return
            }
            textView.window?.makeFirstResponder(textView)
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performTextFinderAction(sender)
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
                layout.addTemporaryAttributes([.foregroundColor: NSColor.tertiaryLabelColor],
                                              forCharacterRange: range)
            }
        }
    }
}

/// An `NSTextView` that opts into vibrancy, so its glyphs are blended against
/// whatever is behind the window rather than painted at a fixed colour.
///
/// Also the place images come in. The view is plain text, so a pasted image
/// cannot become an attachment the way it does in Stickies; instead it is
/// handed out through `onImages` and comes back as a line of markdown.
private final class VibrantTextView: NSTextView {
    override var allowsVibrancy: Bool { true }

    var onImages: (([NSImage]) -> String?)?

    /// A plain-text view only admits string types, so with an image on the
    /// clipboard AppKit greys out Paste and ⌘V never arrives. Declaring the
    /// image types readable is what turns the menu item on.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff, .fileURL]
    }

    // MARK: - Paste

    // A plain-text view routes ⌘V to `pasteAsPlainText:`, not `paste:`;
    // both are covered so the menu item and the shortcut behave the same.
    override func paste(_ sender: Any?) {
        if pasteImages() { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if pasteImages() { return }
        super.pasteAsPlainText(sender)
    }

    private func pasteImages() -> Bool {
        let images = Self.images(on: NSPasteboard.general)
        guard !images.isEmpty else { return false }
        return insertImages(images, at: selectedRange().location)
    }

    // MARK: - Drag

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !Self.images(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !Self.images(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = Self.images(on: sender.draggingPasteboard)
        guard !images.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        return insertImages(images, at: characterIndexForInsertion(at: point))
    }

    // MARK: - Insertion

    /// Puts the markdown for the images in its own paragraph at `index`,
    /// blank line either side, so other renderers read it as a block rather
    /// than a picture glued into a sentence. Goes through `insertText` so it
    /// is undoable and the delegate hears about it like any keystroke.
    @discardableResult
    private func insertImages(_ images: [NSImage], at index: Int) -> Bool {
        guard let markdown = onImages?(images) else { return false }
        let text = string as NSString
        let location = min(index, text.length)
        let before = text.substring(to: location)
        let after = text.substring(from: location)

        var snippet = markdown + "\n"
        if !before.isEmpty && !before.hasSuffix("\n\n") {
            snippet = (before.hasSuffix("\n") ? "\n" : "\n\n") + snippet
        }
        if !after.isEmpty && !after.hasPrefix("\n") {
            snippet += "\n"
        }

        insertText(snippet, replacementRange: NSRange(location: location, length: 0))
        return true
    }

    // MARK: - Pasteboard

    /// Same lookup as Stickies: image files first, so a Finder drag of a
    /// JPEG reads the file rather than the icon, then raw image data for
    /// screenshots and browser drags.
    static func images(on pasteboard: NSPasteboard) -> [NSImage] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let files = urls.filter { url in
                UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) ?? false
            }.compactMap { NSImage(contentsOf: $0) }
            if !files.isEmpty { return files }
        }
        return (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage]) ?? []
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
