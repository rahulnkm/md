import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app on appear, so quitting can flush a pending autosave.
    var store: FolderStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Control-F as a second route to find-in-file, for hands that reach
        // for it. A local monitor sees the key before any view does.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .control, event.charactersIgnoringModifiers == "f" {
                self?.store?.findInFile()
                return nil
            }
            // Escape closes the search modal wherever focus happens to be.
            if event.keyCode == 53, self?.store?.searching == true {
                self?.store?.closeSearch()
                return nil
            }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveNow()
    }
}

/// Reaches the hosting `NSWindow` to make it transparent, so the frosted
/// background shows through instead of the default window material.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no window until it is in the hierarchy, so configure on
        // the next pass of the run loop.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
