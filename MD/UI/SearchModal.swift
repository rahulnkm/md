import SwiftUI
import AppKit

/// Command-palette style search over every file in the folder. Opens from
/// the sidebar's magnifier or ⌘K, floats over the window, and is driven from
/// the keyboard: type, arrow, Return. Escape or a click outside closes it.
struct SearchModal: View {
    @ObservedObject var store: FolderStore

    @State private var query = ""
    @State private var documents: [SearchDocument] = []
    @State private var hits: [SearchHit] = []
    @State private var selected = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Scrim: dims the window and swallows the click that closes.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { store.closeSearch() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    SearchField(text: $query,
                                placeholder: "Search all files",
                                onMove: move,
                                onSubmit: open,
                                onCancel: { store.closeSearch() })
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                if hits.isEmpty {
                    Text(query.isEmpty ? "No files." : "Nothing matches \"\(query)\".")
                        .font(Theme.uiSans(size: 12))
                        .foregroundColor(.secondary)
                        .padding(14)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 1) {
                                ForEach(Array(hits.enumerated()), id: \.element.url) { index, hit in
                                    row(hit, isSelected: index == selected)
                                        .id(hit.url)
                                        .onTapGesture { selected = index; open() }
                                }
                            }
                            .padding(6)
                        }
                        // Hug the rows rather than reserve a fixed height, so
                        // two hits make a short panel and thirty make a
                        // scrolling one.
                        .frame(height: listHeight)
                        .onChange(of: selected) { _ in
                            if let hit = hits.indices.contains(selected) ? hits[selected] : nil {
                                proxy.scrollTo(hit.url, anchor: nil)
                            }
                        }
                    }
                }
            }
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .padding(.top, 72)
        }
        .onAppear {
            documents = store.searchDocuments()
            hits = FileSearch.search(query, in: documents)
        }
        .onChange(of: query) { value in
            hits = FileSearch.search(value, in: documents)
            selected = 0
        }
    }

    private func row(_ hit: SearchHit, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.name)
                .font(Theme.uiSans(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
            if let snippet = hit.snippet {
                Text(snippet)
                    .font(Theme.uiFont(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.12 : 0))
        )
        .contentShape(Rectangle())
    }

    /// Row heights are fixed by their fonts, so the list can be sized
    /// from the hit count rather than measured.
    private var listHeight: CGFloat {
        let rows = hits.reduce(CGFloat(0)) { $0 + ($1.snippet == nil ? 28 : 43) + 1 }
        return min(360, rows + 12)
    }

    private func move(_ delta: Int) {
        guard !hits.isEmpty else { return }
        selected = (selected + delta + hits.count) % hits.count
    }

    private func open() {
        guard hits.indices.contains(selected) else { return }
        let url = hits[selected].url
        store.closeSearch()
        store.select(url)
    }
}

/// The modal's text field. An AppKit field rather than SwiftUI's, because the
/// arrow keys and Return have to drive the list below it and SwiftUI on
/// macOS 13 offers no way to catch them. The field is the first responder
/// the moment it appears, so typing starts without a click.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.sans(size: 15)
        field.textColor = .labelColor
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: Theme.sans(size: 15)])
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // No window yet at make time; focus once it has one.
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Arrow keys, Return and Escape arrive here as editing commands
        /// before the field acts on them.
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):         parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):       parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):  parent.onSubmit()
            // Escape reaches a field editor as `complete:` (autocompletion)
            // rather than `cancelOperation:`, so both mean close.
            case #selector(NSResponder.cancelOperation(_:)),
                 #selector(NSStandardKeyBindingResponding.complete(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }
}
