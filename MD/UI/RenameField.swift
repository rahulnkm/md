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
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.uiFont(size: size))
            .foregroundColor(Theme.text)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onSubmit { commit() }
            // Escape reaches the field as a cancel action rather than a key press.
            .onExitCommand { onCancel() }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.text.opacity(0.14))
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
            onCancel()
            return
        }
        onCommit(trimmed)
    }
}
