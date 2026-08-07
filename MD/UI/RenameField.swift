import SwiftUI

/// Inline filename editor. Used in two places - the sidebar row and the title
/// in the hover chrome - so both entry points behave identically.
///
/// Return commits, Escape cancels, and clicking away commits, which is what
/// Finder does.
struct RenameField: View {
    let initialName: String
    let size: CGFloat
    var alignment: TextAlignment = .leading
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.uiFont(size: size))
            .foregroundColor(.primary)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onSubmit { commit() }
            // Escape reaches the field as a cancel action rather than a key press.
            .onExitCommand { finish(onCancel) }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.14))
            )
            .onAppear {
                text = initialName
                focused = true
            }
            .onChange(of: focused) { isFocused in
                // Losing focus means the user clicked elsewhere; keep the edit.
                if !isFocused { commit() }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != initialName else {
            finish(onCancel)
            return
        }
        finish { onCommit(trimmed) }
    }

    /// Runs the handler once and once only.
    ///
    /// Return commits, which tears the field down, which drops focus, which
    /// would fire the focus-loss commit a second time against a path that has
    /// already moved.
    private func finish(_ action: () -> Void) {
        guard !finished else { return }
        finished = true
        action()
    }
}
