import Foundation

/// One markdown file in the current folder. Metadata only - the body is read
/// on demand, so opening a large folder does not read every file.
struct MDFile: Identifiable, Equatable, Hashable {
    var url: URL
    var modifiedAt: Date

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Something the user needs to see and act on. Never dismissed silently.
enum Banner: Equatable {
    case conflict           // file on disk is newer than the open buffer
    case deleted            // file vanished while open
    case saveFailed(String) // OS-level write failure
    case notText            // file is not valid UTF-8
    case folderUnavailable

    var message: String {
        switch self {
        case .conflict:            return "This file changed on disk."
        case .deleted:             return "This file was deleted."
        case .saveFailed(let why): return "Couldn't save. \(why)"
        case .notText:             return "Not a text file."
        case .folderUnavailable:   return "That folder is no longer available."
        }
    }
}

enum Mode {
    case edit, view
}

/// An in-progress rename.
///
/// The source matters: the sidebar row and the title in the hover chrome are
/// both bound to this, and without it both would put up a text field for the
/// same file and fight over keyboard focus.
struct RenameTarget: Equatable {
    enum Source { case sidebar, titleBar }

    var url: URL
    var source: Source
}
