import SwiftUI

/// File list. Sits on the same frosted background as the editor, separated by
/// a hairline rather than its own material, so the window reads as one pane.
struct SidebarView: View {
    @ObservedObject var store: FolderStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(store.files) { file in
                    row(for: file)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, Theme.topPadding)
            .padding(.bottom, Theme.innerPadding)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func row(for file: MDFile) -> some View {
        let isSelected = store.selection == file.url
        let isUnsaved = isSelected && store.isDirty

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if store.renaming == RenameTarget(url: file.url, source: .sidebar) {
                    RenameField(initialName: file.name,
                                size: 12,
                                onCommit: { store.commitRename(file.url, to: $0) },
                                onCancel: { store.cancelRename() })
                } else {
                    Text(file.name)
                        .font(Theme.uiFont(size: 12))
                        .foregroundColor(Theme.text.opacity(isSelected ? 1.0 : 0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(Self.relativeDate(file.modifiedAt))
                    .font(Theme.uiFont(size: 10))
                    .foregroundColor(Theme.text.opacity(0.45))
            }

            Spacer(minLength: 0)

            // Same stoplight yellow Stickies uses for a visible note.
            Circle()
                .fill(Theme.stoplightYellow)
                .frame(width: 6, height: 6)
                .opacity(isUnsaved ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.text.opacity(isSelected ? 0.10 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { store.select(file.url) }
        .contextMenu {
            Button("Rename") { store.beginRename(file.url, from: .sidebar) }
            Button("Show in Finder") { store.revealInFinder(file.url) }
            Divider()
            Button("Delete…", role: .destructive) { store.requestDelete(file.url) }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Matches the relative date formatting in Stickies' Manager window.
    static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
