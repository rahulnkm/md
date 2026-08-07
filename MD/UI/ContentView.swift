import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: FolderStore

    @State private var chromeHovering = false
    @State private var hoverHideTask: DispatchWorkItem?

    /// A title-bar rename pins the chrome open; a sidebar rename does not need to.
    private var chromeVisible: Bool {
        chromeHovering || store.renaming?.source == .titleBar
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Vibrancy, not a painted colour: foreground styles layered on a
            // Material are blended against the real backdrop by the window
            // server, so text stays legible over a wallpaper the app cannot see.
            Rectangle().fill(store.tint.material)
            if let overlay = store.tint.overlay {
                Rectangle().fill(overlay)
            }

            if store.folderURL == nil {
                emptyState
            } else {
                HStack(spacing: 0) {
                    SidebarView(store: store)
                        .frame(width: Theme.sidebarWidth)
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)
                    detail
                }
            }

        }
        // The chrome is an overlay rather than another ZStack layer so it sits
        // above the AppKit-hosted editor, which otherwise wins hit-testing for
        // the strip and leaves it dead over the right-hand column.
        .overlay(alignment: .top) {
            chrome
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: Theme.topPadding)
        }
        .ignoresSafeArea()
        // Each surface pins its own scheme, so the window stops following the
        // system and the text always matches the glass it sits on.
        .preferredColorScheme(store.tint.colorScheme)
        // Tracked on the whole window and filtered by height. `onHover` on the
        // strip alone never fires where an NSView sits underneath it.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): handleHover(point.y <= Theme.topPadding)
            case .ended:             handleHover(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refresh()
        }
        .alert("Delete \(store.pendingDelete?.lastPathComponent ?? "")?",
               isPresented: Binding(get: { store.pendingDelete != nil },
                                    set: { if !$0 { store.cancelDelete() } })) {
            Button("Cancel", role: .cancel) { store.cancelDelete() }
            // `.destructive` is what makes the button red.
            Button("Delete", role: .destructive) { store.confirmDelete() }
        } message: {
            Text("It moves to the Trash, so you can get it back from there.")
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if let banner = store.banner {
                bannerView(banner)
            }

            if store.selection == nil {
                Spacer()
                Text("No file selected")
                    .font(Theme.uiFont(size: 12))
                    .foregroundColor(Color.primary.opacity(0.55))
                Spacer()
            } else if store.mode == .edit {
                EditorView(text: store.buffer,
                           revision: store.revision,
                           onChange: { store.buffer = $0 })
                    .padding(.top, store.banner == nil ? Theme.topPadding : Theme.innerPadding)
                    .padding(.horizontal, Theme.innerPadding)
                    .padding(.bottom, Theme.innerPadding)
            } else {
                ScrollView {
                    MarkdownView(blocks: MarkdownParser.parse(store.buffer))
                        .padding(.top, store.banner == nil ? Theme.topPadding : Theme.innerPadding)
                        .padding(.horizontal, Theme.innerPadding)
                        .padding(.bottom, Theme.innerPadding)
                }
            }
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 10) {
            Text(banner.message)
                .font(Theme.uiFont(size: 11))
                .foregroundColor(Color.primary)

            Spacer(minLength: 0)

            switch banner {
            case .conflict:
                bannerButton("Reload") { store.reload() }
                bannerButton("Overwrite") { store.overwrite() }
            case .deleted:
                bannerButton("Save as new") { store.saveAsNew() }
            case .saveFailed:
                bannerButton("Retry") { store.overwrite() }
            case .folderUnavailable:
                bannerButton("Choose folder") { store.chooseFolder() }
            case .notText:
                bannerButton("Dismiss") { store.banner = nil }
            }
        }
        .padding(.horizontal, Theme.innerPadding)
        .padding(.vertical, 8)
        .padding(.top, Theme.topPadding - 8)
        .background(Theme.stoplightYellow.opacity(0.12))
    }

    private func bannerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.uiFont(size: 11))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("md")
                .font(Theme.uiSemibold(size: 20))
                .foregroundColor(Color.primary)
            Text("Pick the folder your markdown files live in.")
                .font(Theme.uiFont(size: 12))
                .foregroundColor(Color.secondary)
            bannerButton("Choose folder") { store.chooseFolder() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hover chrome

    /// Invisible until the top strip is hovered, matching Stickies. Swatches
    /// left, filename centre, mode toggle right.
    private var chrome: some View {
        ZStack {
            // Transparent layer that catches hover across the whole strip.
            Color.clear
                .contentShape(Rectangle())
                .onHover(perform: handleHover)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(TintStyle.allCases, id: \.self) { style in
                        TintSwatch(style: style, isSelected: store.tint == style) {
                            store.tint = style
                        }
                    }
                }
                .padding(.leading, 78)   // clear of the traffic lights
                .onHover(perform: handleHover)

                Spacer()

                if let selection = store.selection {
                    if store.renaming == RenameTarget(url: selection, source: .titleBar) {
                        RenameField(initialName: selection.deletingPathExtension().lastPathComponent,
                                    size: 11,
                                    alignment: .center,
                                    onCommit: { store.commitRename(selection, to: $0) },
                                    onCancel: { store.cancelRename() })
                            .frame(maxWidth: 240)
                    } else {
                        Text(selection.lastPathComponent)
                            .font(Theme.uiFont(size: 11))
                            .foregroundColor(Color.secondary)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { store.beginRename(selection, from: .titleBar) }
                            .onHover(perform: handleHover)
                            .help("Double-click to rename")
                    }
                }

                Spacer()

                if store.selection != nil {
                    Button(action: { store.toggleMode() }) {
                        Text(store.mode == .edit ? "Preview" : "Edit")
                            .font(Theme.uiFont(size: 11))
                            .foregroundColor(Color.primary.opacity(0.85))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, Theme.dotInset)
                    .onHover(perform: handleHover)
                    .help("Toggle Edit and Preview (⌘E)")
                }
            }
            // Stays up during a rename, or the text field would disappear from
            // under the cursor the moment it left the strip.
            .opacity(chromeVisible ? 0.9 : 0)
            .allowsHitTesting(chromeVisible)
            .animation(.easeInOut(duration: 0.12), value: chromeVisible)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.topPadding, alignment: .top)
    }

    /// Debounced so the false/true flip as the cursor crosses onto a child
    /// button is cancelled before it commits. Same 120ms as Stickies.
    private func handleHover(_ isHovering: Bool) {
        hoverHideTask?.cancel()
        if isHovering {
            chromeHovering = true
        } else {
            let task = DispatchWorkItem { chromeHovering = false }
            hoverHideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
        }
    }
}

private struct TintSwatch: View {
    let style: TintStyle
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(white: style.swatchLightness))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(Color.primary, lineWidth: isSelected ? 1.0 : 0)
                )
                // Tight horizontal gap; vertical padding keeps the hit target
                // tall enough to click comfortably.
                .padding(EdgeInsets(top: 8, leading: 3, bottom: 8, trailing: 3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.rawValue.capitalized)
    }
}
