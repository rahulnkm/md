import SwiftUI

@main
struct MDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = FolderStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 660, minHeight: 440)
                .background(WindowConfigurator())
                .onAppear { delegate.store = store }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") { store.newFile() }
                    .keyboardShortcut("n")
                Button("Choose Folder…") { store.chooseFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(!store.isDirty)
            }
            // Find lives in Edit, where every Mac app keeps it. ⌘F searches
            // the open file; ⌘K searches every file, the command-palette
            // reflex. Control-F is handled in the AppDelegate, since a menu
            // item can carry only one shortcut.
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find in File") { store.findInFile() }
                    .keyboardShortcut("f")
                    .disabled(store.selection == nil)
                Button("Search All Files…") { store.openSearch() }
                    .keyboardShortcut("k")
                    .disabled(store.folderURL == nil)
            }
            // Appended into the built-in View menu. A `CommandMenu("View")`
            // would sit alongside it and put two View menus in the menu bar.
            CommandGroup(after: .toolbar) {
                Button(store.mode == .edit ? "Preview" : "Edit") { store.toggleMode() }
                    .keyboardShortcut("e")
                Divider()
                Button("Previous File") { store.step(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Next File") { store.step(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
        }
    }
}
