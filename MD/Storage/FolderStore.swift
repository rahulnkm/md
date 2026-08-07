import SwiftUI
import AppKit

/// Owns the folder, the file list, and the buffer for the open file.
///
/// The folder on disk is the source of truth. Nothing is cached beyond the
/// current buffer, so any other tool can edit the same files.
@MainActor
final class FolderStore: ObservableObject {

    @Published private(set) var folderURL: URL?
    @Published private(set) var files: [MDFile] = []
    @Published private(set) var selection: URL?
    @Published var buffer: String = "" { didSet { bufferChanged() } }
    @Published private(set) var isDirty = false
    /// Bumped whenever the buffer is replaced from outside the editor, so the
    /// text view knows to take the new contents rather than keep its own.
    @Published private(set) var revision = 0
    /// The in-progress rename, if any, and where it was started from.
    @Published var renaming: RenameTarget?
    /// File awaiting delete confirmation. Set means the dialog is up.
    @Published var pendingDelete: URL?
    @Published var banner: Banner?
    @Published var mode: Mode = .edit
    /// Defaults darker than Stickies' `.slate`. A sticky note is small and sits
    /// over whatever happens to be behind it; a full window over a bright
    /// desktop needs more tint before body text is comfortable to read.
    @Published var tint: TintStyle = .obsidian { didSet { defaults.set(tint.rawValue, forKey: Keys.tint) } }

    private enum Keys {
        static let folder = "folderPath"
        static let tint = "tintStyle"
    }

    private let defaults: UserDefaults
    private let fileManager = FileManager.default

    /// Modification date the buffer was read at, used to spot outside edits.
    private var loadedModifiedAt: Date?
    /// True until a file created with New has taken its name from a heading.
    private var awaitingSlug = false
    private var autosave: DispatchWorkItem?

    private static let autosaveDelay: TimeInterval = 0.8
    /// Name a new file carries until it is renamed or takes one from a heading.
    static let defaultName = "Untitled"

    /// `defaults` is injectable so tests get their own store rather than
    /// picking up the real app's remembered folder and opening it.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.tint), let saved = TintStyle(rawValue: raw) {
            tint = saved
        }
        if let path = defaults.string(forKey: Keys.folder) {
            open(folder: URL(fileURLWithPath: path), remember: false)
        }
    }

    // MARK: - Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick the folder your markdown files live in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveNow()
        open(folder: url, remember: true)
    }

    /// Opens a folder. `remember: false` skips persisting it, which is what
    /// restoring on launch and the tests both want.
    func open(folder rawFolder: URL, remember: Bool) {
        let folder = Self.normalized(rawFolder)
        guard fileManager.fileExists(atPath: folder.path) else {
            banner = .folderUnavailable
            return
        }

        // Switching folders has to drop the open file with it. Carrying the
        // selection across leaves it pointing at a path the new listing knows
        // nothing about, which reads to the user as "this file was deleted".
        if folder != folderURL {
            autosave?.cancel()
            selection = nil
            setBufferWithoutDirtying("")
            loadedModifiedAt = nil
            banner = nil
        }

        folderURL = folder
        if remember { defaults.set(folder.path, forKey: Keys.folder) }
        refresh()
        if selection == nil, let first = files.first { select(first.url) }
    }

    /// Re-reads the folder. Called on window focus and after every save rather
    /// than run from a filesystem watcher - a watcher is a background process
    /// and a source of bugs, and focus covers the real case of editing
    /// elsewhere.
    func refresh() {
        guard let folder = folderURL else { return }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            banner = .folderUnavailable
            files = []
            return
        }

        files = entries
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                // Directory listings come back with `/private` prefixed; hand-built
                // URLs do not. Both sides go through `normalized` so they compare equal.
                return MDFile(url: Self.normalized(url), modifiedAt: date)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // The open file may have been deleted from under us.
        if let current = selection, !files.contains(where: { $0.url == current }) {
            banner = .deleted
        }
    }

    // MARK: - Selection

    func select(_ rawURL: URL?) {
        let url = rawURL.map(Self.normalized)
        guard url != selection else { return }
        saveNow()
        selection = url
        awaitingSlug = false
        banner = nil
        guard let url else {
            setBufferWithoutDirtying("")
            loadedModifiedAt = nil
            return
        }
        load(url)
    }

    private func load(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            setBufferWithoutDirtying(text)
            loadedModifiedAt = modificationDate(of: url)
        } catch {
            // A read failure here is almost always a non-UTF-8 file; the app
            // deliberately refuses rather than mangling it.
            setBufferWithoutDirtying("")
            loadedModifiedAt = nil
            banner = .notText
        }
    }

    /// Steps through the sidebar. Wraps at both ends.
    func step(_ delta: Int) {
        guard !files.isEmpty else { return }
        guard let current = selection,
              let index = files.firstIndex(where: { $0.url == current }) else {
            select(files.first?.url)
            return
        }
        let next = (index + delta + files.count) % files.count
        select(files[next].url)
    }

    // MARK: - Editing

    private func setBufferWithoutDirtying(_ text: String) {
        autosave?.cancel()
        suppressDirty = true
        buffer = text
        suppressDirty = false
        isDirty = false
        revision += 1
    }

    private var suppressDirty = false

    private func bufferChanged() {
        guard !suppressDirty else { return }
        isDirty = true
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }
        autosave = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: task)
    }

    func toggleMode() {
        mode = (mode == .edit) ? .view : .edit
    }

    // MARK: - Saving

    /// Saves if there is anything to save, refusing when the file on disk has
    /// moved ahead of the buffer.
    func save() {
        guard let url = selection, isDirty else { return }

        if let loaded = loadedModifiedAt, let disk = modificationDate(of: url),
           disk.timeIntervalSince(loaded) > 1 {
            banner = .conflict
            return
        }
        write(to: url)
    }

    /// Save without the conflict check. Reached only from the conflict banner.
    func overwrite() {
        guard let url = selection else { return }
        banner = nil
        write(to: url)
    }

    /// Discard the buffer and take what is on disk.
    func reload() {
        guard let url = selection else { return }
        banner = nil
        load(url)
    }

    /// Writes the buffer somewhere new, for when the original file is gone.
    func saveAsNew() {
        guard let folder = folderURL else { return }
        banner = nil
        let base = selection?.deletingPathExtension().lastPathComponent ?? Self.defaultName
        let url = uniqueURL(named: base, in: folder)
        selection = url
        write(to: url)
    }

    /// Flushes a pending autosave. Called before anything that would lose the
    /// buffer: switching files, changing folder, quitting.
    func saveNow() {
        autosave?.cancel()
        save()
    }

    private func write(to url: URL) {
        var target = url
        var discardAfterWrite: URL?

        // A file created by New borrows its name from the first heading, once.
        // After that the filename is fixed and never moves on its own.
        if awaitingSlug, let slug = slug(from: buffer), let folder = folderURL {
            let renamed = uniqueURL(named: slug, in: folder)
            if renamed != url {
                // Note the old path but do not delete it yet. Deleting first
                // would lose the file outright if the write then failed.
                discardAfterWrite = url
                target = renamed
            }
            awaitingSlug = false
        }

        do {
            try Data(buffer.utf8).write(to: target, options: .atomic)
        } catch {
            banner = .saveFailed(error.localizedDescription)
            return
        }

        if let stale = discardAfterWrite {
            try? fileManager.removeItem(at: stale)
            selection = target
        }

        isDirty = false
        loadedModifiedAt = modificationDate(of: target)
        banner = nil
        refresh()
    }

    // MARK: - New file

    func newFile() {
        guard let folder = folderURL else { chooseFolder(); return }
        saveNow()
        let url = uniqueURL(named: Self.defaultName, in: folder)
        guard (try? Data().write(to: url, options: .atomic)) != nil else {
            banner = .saveFailed("Couldn't create a file in that folder.")
            return
        }
        refresh()
        selection = url
        setBufferWithoutDirtying("")
        loadedModifiedAt = modificationDate(of: url)
        awaitingSlug = true
        mode = .edit
        banner = nil
    }

    // MARK: - Renaming

    /// Puts a file into rename mode. The sidebar row and the title in the
    /// hover chrome both watch this and swap in a text field.
    func beginRename(_ url: URL? = nil, from source: RenameTarget.Source) {
        guard let target = url ?? selection else { return }
        renaming = RenameTarget(url: Self.normalized(target), source: source)
    }

    func cancelRename() { renaming = nil }

    /// Moves the file. An explicit name always wins, so a file renamed before
    /// its first save no longer takes a name from its heading.
    func commitRename(_ url: URL, to rawName: String) {
        renaming = nil
        guard let folder = folderURL else { return }

        let base = Self.sanitizeFilename(rawName)
        guard !base.isEmpty else { return }

        let source = Self.normalized(url)
        // Built literally, not through `normalized`. That resolves the path
        // against the filesystem, and on a case-insensitive volume resolution
        // hands back the spelling already on disk - so "Scratch.md" would come
        // back as "scratch.md", match the source, and the rename would return
        // as a no-op with nothing to show for it.
        let target = folder.appendingPathComponent("\(base).md").standardizedFileURL
        guard target.path != source.path else { return }

        // macOS volumes are case-insensitive by default, so `fileExists`
        // answers yes for "Scratch.md" when only "scratch.md" is there. Taking
        // that at face value makes a file collide with itself and blocks any
        // change of capitalisation. Only a genuinely different file counts.
        if fileManager.fileExists(atPath: target.path), !isSameFile(target, source) {
            banner = .saveFailed("A file named \(base).md already exists.")
            return
        }

        // Flush the buffer first so a pending autosave can't write to the old
        // path after the move.
        if source == selection { saveNow() }

        do {
            try move(from: source, to: target)
        } catch {
            banner = .saveFailed(error.localizedDescription)
            return
        }

        if source == selection {
            // Safe to normalize now: the file exists under the new spelling,
            // so resolution returns that rather than the old one, and this
            // matches what the directory listing will report.
            let renamed = Self.normalized(target)
            selection = renamed
            loadedModifiedAt = modificationDate(of: renamed)
            awaitingSlug = false
        }
        refresh()
    }

    /// Are these two paths the same file on disk? Compares the volume's own
    /// identifier rather than the path text, which is the only way to tell a
    /// case-only rename apart from a real collision.
    private func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let idA = (try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier
        let idB = (try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier
        guard let idA, let idB else { return false }
        return idA.isEqual(idB)
    }

    /// Moves a file, handling the case-only rename that a direct move refuses
    /// on a case-insensitive volume because the destination "already exists".
    /// Goes via a hidden staging name and puts the file back if the second
    /// step fails, so there is no window where the file is missing.
    private func move(from source: URL, to target: URL) throws {
        guard fileManager.fileExists(atPath: target.path) else {
            try fileManager.moveItem(at: source, to: target)
            return
        }

        let staging = source.deletingLastPathComponent()
            .appendingPathComponent(".md-rename-\(UUID().uuidString)")
        try fileManager.moveItem(at: source, to: staging)
        do {
            try fileManager.moveItem(at: staging, to: target)
        } catch {
            try? fileManager.moveItem(at: staging, to: source)
            throw error
        }
    }

    // MARK: - Deleting

    /// Asks for confirmation. Nothing is removed until `confirmDelete`.
    func requestDelete(_ url: URL) {
        pendingDelete = Self.normalized(url)
    }

    func cancelDelete() { pendingDelete = nil }

    /// Moves the file to the Trash - never an unrecoverable delete - and lands
    /// the selection on the neighbour that took its place.
    func confirmDelete() {
        guard let url = pendingDelete else { return }
        pendingDelete = nil

        // Note the row position before the list changes underneath us.
        let position = files.firstIndex { $0.url == url }
        let wasSelected = (url == selection)

        if wasSelected {
            // Drop the buffer first so a pending autosave cannot recreate the
            // file at the path we are about to empty. Cleared here rather than
            // through `select(nil)`, which short-circuits once selection is
            // already nil and would leave the deleted file's text on screen.
            autosave?.cancel()
            isDirty = false
            selection = nil
            setBufferWithoutDirtying("")
            loadedModifiedAt = nil
        }

        do {
            try trash(url)
        } catch {
            if wasSelected { select(url) }
            banner = .saveFailed(error.localizedDescription)
            return
        }

        banner = nil
        refresh()

        guard wasSelected else { return }
        // Land on whatever slid into that row, or the last file if it was the
        // bottom one.
        if let position, !files.isEmpty {
            select(files[min(position, files.count - 1)].url)
        } else {
            select(files.first?.url)
        }
    }

    /// Seam so tests can delete without filling the real Trash.
    var trash: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Reveals the file in Finder, with the file itself selected.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Strips anything that would make the name a path or a second extension.
    nonisolated static func sanitizeFilename(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        for bad in ["/", ":", "\n", "\t"] {
            name = name.replacingOccurrences(of: bad, with: "-")
        }
        // A leading dot would hide the file from the listing, which filters
        // hidden entries - the file would silently vanish.
        while name.hasPrefix(".") { name.removeFirst() }
        return name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Naming

    /// `Untitled.md`, then `Untitled (1).md`, `Untitled (2).md`, and so on -
    /// the same shape Finder uses for copies.
    private func uniqueURL(named base: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent("\(base).md")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(counter)).md")
            counter += 1
        }
        return candidate
    }

    /// A filename built from the first `# heading`, or nil if there isn't one.
    /// Pure, so it carries no actor isolation and is testable on its own.
    nonisolated static func slug(from body: String) -> String? {
        guard let firstLine = body.split(separator: "\n", maxSplits: 1,
                                         omittingEmptySubsequences: false).first else { return nil }
        let line = firstLine.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("#") else { return nil }

        let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        var slug = ""
        for char in title.lowercased() {
            if char.isLetter || char.isNumber {
                slug.append(char)
            } else if !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? nil : String(slug.prefix(60))
    }

    private func slug(from body: String) -> String? { Self.slug(from: body) }

    /// Read through `FileManager` rather than `URL.resourceValues`, which
    /// caches on the URL instance. A cached date would make outside edits
    /// invisible and let the app silently overwrite them.
    private func modificationDate(of url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Resolves symlinks so URLs built by hand compare equal to URLs that came
    /// back from a directory listing. `/var` versus `/private/var` otherwise
    /// breaks every `files.contains(selection)` check.
    private static func normalized(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
