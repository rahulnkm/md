import XCTest
@testable import MD

final class SlugTests: XCTestCase {

    func testSlugFromHeading() {
        XCTAssertEqual(FolderStore.slug(from: "# Hello World"), "hello-world")
    }

    func testPunctuationCollapsesToSingleDashes() {
        XCTAssertEqual(FolderStore.slug(from: "# What's *next*, really?"), "what-s-next-really")
    }

    func testNoHeadingMeansNoSlug() {
        XCTAssertNil(FolderStore.slug(from: "just a paragraph"))
    }

    func testHeadingMustBeTheFirstLine() {
        XCTAssertNil(FolderStore.slug(from: "intro\n# Heading"))
    }

    func testEmptyHeadingMeansNoSlug() {
        XCTAssertNil(FolderStore.slug(from: "#"))
        XCTAssertNil(FolderStore.slug(from: "#   "))
    }

    func testPunctuationOnlyHeadingMeansNoSlug() {
        XCTAssertNil(FolderStore.slug(from: "# ???"))
    }

    func testLongHeadingIsTruncated() {
        let slug = FolderStore.slug(from: "# " + String(repeating: "a", count: 200))
        XCTAssertEqual(slug?.count, 60)
    }
}

@MainActor
final class FolderStoreTests: XCTestCase {

    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("md-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func write(_ name: String, _ body: String) {
        try? Data(body.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func makeStore() -> FolderStore {
        let store = FolderStore()
        store.open(folder: folder, remember: false)
        return store
    }

    func testListsOnlyMarkdownFilesSorted() {
        write("b.md", "b")
        write("a.md", "a")
        write("notes.txt", "ignored")

        let store = makeStore()
        XCTAssertEqual(store.files.map(\.name), ["a", "b"])
    }

    func testSelectingLoadsTheBody() {
        write("a.md", "# Title")
        let store = makeStore()
        store.select(folder.appendingPathComponent("a.md"))
        XCTAssertEqual(store.buffer, "# Title")
        XCTAssertFalse(store.isDirty)
    }

    func testEditingMarksDirtyAndSaveWritesToDisk() throws {
        write("a.md", "old")
        let store = makeStore()
        store.select(folder.appendingPathComponent("a.md"))

        store.buffer = "new"
        XCTAssertTrue(store.isDirty)

        store.saveNow()
        XCTAssertFalse(store.isDirty)

        let onDisk = try String(contentsOf: folder.appendingPathComponent("a.md"), encoding: .utf8)
        XCTAssertEqual(onDisk, "new")
    }

    func testSwitchingFilesSavesTheOutgoingBuffer() throws {
        write("a.md", "a")
        write("b.md", "b")
        let store = makeStore()

        store.select(folder.appendingPathComponent("a.md"))
        store.buffer = "edited"
        store.select(folder.appendingPathComponent("b.md"))

        let onDisk = try String(contentsOf: folder.appendingPathComponent("a.md"), encoding: .utf8)
        XCTAssertEqual(onDisk, "edited")
        XCTAssertEqual(store.buffer, "b")
    }

    func testNewFileTakesItsNameFromTheFirstHeading() {
        let store = makeStore()
        store.newFile()
        XCTAssertEqual(store.selection?.lastPathComponent, "Untitled.md")

        store.buffer = "# Meeting Notes"
        store.saveNow()

        XCTAssertEqual(store.selection?.lastPathComponent, "meeting-notes.md")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("Untitled.md").path))
    }

    /// After the one-time rename the filename is fixed, even if the heading changes.
    func testFilenameIsFixedAfterTheFirstRename() {
        let store = makeStore()
        store.newFile()
        store.buffer = "# First"
        store.saveNow()

        store.buffer = "# Second"
        store.saveNow()

        XCTAssertEqual(store.selection?.lastPathComponent, "first.md")
    }

    func testNewFileWithoutAHeadingKeepsUntitled() {
        let store = makeStore()
        store.newFile()
        store.buffer = "no heading here"
        store.saveNow()
        XCTAssertEqual(store.selection?.lastPathComponent, "Untitled.md")
    }

    /// Finder's shape for copies: Untitled, Untitled (1), Untitled (2).
    func testRepeatedNewFilesCountUpInParentheses() {
        let store = makeStore()
        store.newFile()
        store.newFile()
        XCTAssertEqual(store.selection?.lastPathComponent, "Untitled (1).md")
        store.newFile()
        XCTAssertEqual(store.selection?.lastPathComponent, "Untitled (2).md")
    }

    func testOutsideEditBlocksSaveAndOffersAChoice() throws {
        write("a.md", "original")
        let store = makeStore()
        let url = folder.appendingPathComponent("a.md")
        store.select(url)

        store.buffer = "mine"
        // Push the on-disk timestamp past the conflict threshold.
        try Data("theirs".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: url.path)

        store.saveNow()
        XCTAssertEqual(store.banner, .conflict)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "theirs")

        store.overwrite()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mine")
        XCTAssertNil(store.banner)
    }

    func testReloadDiscardsTheBuffer() throws {
        write("a.md", "original")
        let store = makeStore()
        store.select(folder.appendingPathComponent("a.md"))
        store.buffer = "scratch"

        store.reload()
        XCTAssertEqual(store.buffer, "original")
        XCTAssertFalse(store.isDirty)
    }

    func testSteppingWrapsAtBothEnds() {
        write("a.md", "")
        write("b.md", "")
        let store = makeStore()
        store.select(folder.appendingPathComponent("a.md"))

        store.step(-1)
        XCTAssertEqual(store.selection?.lastPathComponent, "b.md")
        store.step(1)
        XCTAssertEqual(store.selection?.lastPathComponent, "a.md")
    }

    // MARK: - Renaming

    func testRenameMovesTheFileAndKeepsItSelected() throws {
        write("a.md", "body")
        let store = makeStore()
        let url = folder.appendingPathComponent("a.md")
        store.select(url)

        store.commitRename(store.selection!, to: "Meeting Notes")

        XCTAssertEqual(store.selection?.lastPathComponent, "Meeting Notes.md")
        XCTAssertEqual(store.files.map(\.name), ["Meeting Notes"])
        XCTAssertEqual(store.buffer, "body")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRenameFlushesUnsavedChangesFirst() throws {
        write("a.md", "old")
        let store = makeStore()
        store.select(folder.appendingPathComponent("a.md"))
        store.buffer = "edited"

        store.commitRename(store.selection!, to: "b")

        let onDisk = try String(contentsOf: folder.appendingPathComponent("b.md"), encoding: .utf8)
        XCTAssertEqual(onDisk, "edited")
    }

    func testRenamingAFileThatIsNotOpenLeavesSelectionAlone() {
        write("a.md", "a")
        write("b.md", "b")
        let store = makeStore()
        store.select(folder.appendingPathComponent("a.md"))

        store.commitRename(folder.appendingPathComponent("b.md"), to: "c")

        XCTAssertEqual(store.selection?.lastPathComponent, "a.md")
        XCTAssertEqual(store.files.map(\.name), ["a", "c"])
    }

    func testRenameOntoAnExistingNameIsRefused() {
        write("a.md", "a")
        write("b.md", "b")
        let store = makeStore()

        store.commitRename(folder.appendingPathComponent("a.md"), to: "b")

        XCTAssertEqual(store.banner, .saveFailed("A file named b.md already exists."))
        XCTAssertEqual(store.files.map(\.name), ["a", "b"])
    }

    /// A renamed file must not later rename itself from its heading.
    func testRenameBeatsTheHeadingSlug() {
        let store = makeStore()
        store.newFile()
        store.commitRename(store.selection!, to: "keep this name")

        store.buffer = "# Something Else"
        store.saveNow()

        XCTAssertEqual(store.selection?.lastPathComponent, "keep this name.md")
    }

    /// The heading rename must not delete the original before the new file is
    /// safely on disk.
    func testHeadingRenameLeavesExactlyOneFile() throws {
        let store = makeStore()
        store.newFile()
        store.buffer = "# Notes\n\nbody"
        store.saveNow()

        XCTAssertEqual(store.files.map(\.name), ["notes"])
        let onDisk = try String(contentsOf: store.selection!, encoding: .utf8)
        XCTAssertEqual(onDisk, "# Notes\n\nbody")
    }

    func testSanitizeStripsPathSeparatorsAndExtension() {
        XCTAssertEqual(FolderStore.sanitizeFilename("a/b:c"), "a-b-c")
        XCTAssertEqual(FolderStore.sanitizeFilename("notes.md"), "notes")
        XCTAssertEqual(FolderStore.sanitizeFilename("  spaced  "), "spaced")
        // A leading dot would hide the file from the listing entirely.
        XCTAssertEqual(FolderStore.sanitizeFilename(".hidden"), "hidden")
        XCTAssertEqual(FolderStore.sanitizeFilename("   "), "")
    }

    func testNonUTF8FileIsRefusedRatherThanMangled() {
        let url = folder.appendingPathComponent("binary.md")
        try? Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)

        let store = makeStore()
        store.select(url)
        XCTAssertEqual(store.banner, .notText)
        XCTAssertEqual(store.buffer, "")
    }
}
