import SwiftUI
import AppKit

/// A scroll view that remembers where it was.
///
/// SwiftUI's `ScrollView` on macOS 13 offers no way to read or set its
/// offset, so leaving a file and coming back always landed at the top. This
/// hosts the SwiftUI content inside an `NSScrollView`, reports the offset as
/// it changes, and jumps back to a given offset whenever `key` changes.
struct PositionScrollView<Content: View>: NSViewRepresentable {
    /// Offset to land on when the view appears or `key` changes.
    let offset: CGFloat
    /// Bumped when the content is a different document and `offset` applies.
    let key: Int
    let onScroll: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.scrollerStyle = .overlay

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = hosting
        // Pinned to the clip view's width; height comes from the content.
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        let coordinator = context.coordinator
        coordinator.onScroll = onScroll
        coordinator.key = key
        scroll.contentView.postsBoundsChangedNotifications = true
        coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main
        ) { [weak coordinator, weak scroll] _ in
            guard let coordinator, let scroll, !coordinator.restoring else { return }
            coordinator.onScroll?(scroll.contentView.bounds.origin.y)
        }

        coordinator.restore(scroll, to: offset)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onScroll = onScroll
        (scroll.documentView as? NSHostingView<Content>)?.rootView = content()
        if context.coordinator.key != key {
            context.coordinator.key = key
            context.coordinator.restore(scroll, to: offset)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onScroll: ((CGFloat) -> Void)?
        var key = -1
        var observer: NSObjectProtocol?
        /// True while a programmatic jump is in flight, so the bounds change
        /// it causes is not recorded as the user scrolling to the top.
        var restoring = false

        /// The hosted content has not been laid out when the document
        /// changes, so the jump waits a turn for its height to exist.
        func restore(_ scroll: NSScrollView, to offset: CGFloat) {
            restoring = true
            DispatchQueue.main.async { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                scroll.documentView?.layoutSubtreeIfNeeded()
                let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset, maxY)))
                scroll.reflectScrolledClipView(scroll.contentView)
                self.restoring = false
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
