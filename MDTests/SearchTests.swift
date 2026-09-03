import XCTest
@testable import MD

final class FileSearchTests: XCTestCase {

    private func doc(_ name: String, _ body: String = "") -> SearchDocument {
        SearchDocument(url: URL(fileURLWithPath: "/notes/\(name).md"), name: name, body: body)
    }

    func testEmptyQueryReturnsEverythingInGivenOrder() {
        let docs = [doc("b"), doc("a")]
        XCTAssertEqual(FileSearch.search("", in: docs).map(\.name), ["b", "a"])
    }

    func testKeywordInBodyFindsTheFileWithTheMatchingLineAsSnippet() {
        let docs = [doc("plan", "first line\nship the Widget by friday\nlast"), doc("other", "nothing")]
        let hits = FileSearch.search("widget", in: docs)
        XCTAssertEqual(hits.map(\.name), ["plan"])
        XCTAssertEqual(hits[0].snippet, "ship the Widget by friday")
    }

    func testNameMatchOutranksBodyMatch() {
        let docs = [doc("notes", "budget budget budget"), doc("budget", "some text")]
        XCTAssertEqual(FileSearch.search("budget", in: docs).map(\.name), ["budget", "notes"])
    }

    func testFuzzyMatchesTheNameOutOfOrderCharacters() {
        let docs = [doc("meeting-notes"), doc("harmonic")]
        let hits = FileSearch.search("mtg", in: docs)
        XCTAssertEqual(hits.first?.name, "meeting-notes")
    }

    func testTypoStillLands() {
        let docs = [doc("todo", "call the landlord about the deposit"), doc("misc", "unrelated")]
        XCTAssertEqual(FileSearch.search("landlrd", in: docs).map(\.name), ["todo"])
    }

    func testNoMatchMeansNoHits() {
        XCTAssertEqual(FileSearch.search("zzzz", in: [doc("a", "hello")]), [])
    }

    func testFuzzyScorePrefersTightClusters() {
        let tight = FileSearch.fuzzyScore("abc", in: "xabcx")!
        let loose = FileSearch.fuzzyScore("abc", in: "a--b--c")!
        XCTAssertGreaterThan(tight, loose)
        XCTAssertNil(FileSearch.fuzzyScore("abc", in: "acb"))
    }

    func testLimitCapsResults() {
        let docs = (0..<50).map { doc("note\($0)", "hello") }
        XCTAssertEqual(FileSearch.search("hello", in: docs, limit: 5).count, 5)
    }
}
