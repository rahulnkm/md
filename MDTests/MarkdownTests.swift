import XCTest
@testable import MD

final class BlockParserTests: XCTestCase {

    func testHeadingLevels() {
        XCTAssertEqual(MarkdownParser.parse("# One"), [.heading(level: 1, text: "One")])
        XCTAssertEqual(MarkdownParser.parse("###### Six"), [.heading(level: 6, text: "Six")])
    }

    func testSevenHashesIsNotAHeading() {
        XCTAssertEqual(MarkdownParser.parse("####### Nope"), [.paragraph("####### Nope")])
    }

    /// ATX headings need a space, so hashtags stay prose.
    func testHashWithoutSpaceIsProse() {
        XCTAssertEqual(MarkdownParser.parse("#tag"), [.paragraph("#tag")])
    }

    /// A lone newline is a soft wrap, not a break. Hard-wrapped source has to
    /// render as flowing prose.
    func testSoftWrapJoinsIntoOneLine() {
        XCTAssertEqual(MarkdownParser.parse("one\ntwo"), [.paragraph("one two")])
    }

    func testTwoTrailingSpacesForceABreak() {
        XCTAssertEqual(MarkdownParser.parse("one  \ntwo"), [.paragraph("one\ntwo")])
    }

    func testTrailingBackslashForcesABreak() {
        XCTAssertEqual(MarkdownParser.parse("one\\\ntwo"), [.paragraph("one\ntwo")])
    }

    func testBlankLineSplitsParagraphs() {
        XCTAssertEqual(MarkdownParser.parse("one\n\ntwo"),
                       [.paragraph("one"), .paragraph("two")])
    }

    func testBulletList() {
        let blocks = MarkdownParser.parse("- a\n- b")
        XCTAssertEqual(blocks, [.list(ordered: false, items: [
            ListItem(marker: "-", text: "a", indent: 0),
            ListItem(marker: "-", text: "b", indent: 0),
        ])])
    }

    func testNestedBulletCarriesIndent() {
        let blocks = MarkdownParser.parse("- a\n  - b")
        guard case let .list(_, items) = blocks[0] else { return XCTFail("expected a list") }
        XCTAssertEqual(items.map(\.indent), [0, 1])
    }

    func testOrderedList() {
        let blocks = MarkdownParser.parse("1. a\n2. b")
        XCTAssertEqual(blocks, [.list(ordered: true, items: [
            ListItem(marker: "1.", text: "a", indent: 0),
            ListItem(marker: "2.", text: "b", indent: 0),
        ])])
    }

    func testQuoteRunsTogether() {
        XCTAssertEqual(MarkdownParser.parse("> a\n> b"), [.quote("a b")])
    }

    func testFencedCodeKeepsContentsVerbatim() {
        let source = "```swift\nlet x = 1\n# not a heading\n```"
        XCTAssertEqual(MarkdownParser.parse(source),
                       [.code(language: "swift", code: "let x = 1\n# not a heading")])
    }

    func testUnclosedFenceDoesNotSwallowTheParser() {
        let blocks = MarkdownParser.parse("```\nstuff")
        XCTAssertEqual(blocks, [.code(language: nil, code: "stuff")])
    }

    func testRuleVersusBullet() {
        XCTAssertEqual(MarkdownParser.parse("---"), [.rule])
        XCTAssertEqual(MarkdownParser.parse("- x"),
                       [.list(ordered: false, items: [ListItem(marker: "-", text: "x", indent: 0)])])
    }

    func testEmptyInput() {
        XCTAssertEqual(MarkdownParser.parse(""), [])
    }

    func testStrayQuoteMarkerDoesNotCrash() {
        XCTAssertEqual(MarkdownParser.parse(">"), [.quote("")])
    }

    /// Parsing must not drop text. Every word in must appear somewhere out.
    func testRoundTripLosesNoWords() {
        let source = """
        # Title

        Some **bold** and `code`.

        - one
        - two

        > quoted

        ```
        fenced
        ```
        """
        let words = Set(source.split(whereSeparator: { !$0.isLetter }).map(String.init))
        var rendered = ""
        for block in MarkdownParser.parse(source) {
            switch block {
            case let .heading(_, text):     rendered += text + " "
            case let .paragraph(text):      rendered += text + " "
            case let .quote(text):          rendered += text + " "
            case let .code(_, code):        rendered += code + " "
            case let .list(_, items):       rendered += items.map(\.text).joined(separator: " ") + " "
            case .rule:                     break
            }
        }
        for word in words {
            XCTAssertTrue(rendered.contains(word), "lost \"\(word)\"")
        }
    }
}

final class InlineParserTests: XCTestCase {

    func testPlainText() {
        XCTAssertEqual(InlineParser.parse("hello"), [Span(text: "hello")])
    }

    func testBold() {
        XCTAssertEqual(InlineParser.parse("a **b** c"), [
            Span(text: "a "),
            Span(text: "b", bold: true),
            Span(text: " c"),
        ])
    }

    func testItalicWithAsterisk() {
        XCTAssertEqual(InlineParser.parse("*x*"), [Span(text: "x", italic: true)])
    }

    func testBoldAndItalicNest() {
        XCTAssertEqual(InlineParser.parse("**a *b***"), [
            Span(text: "a ", bold: true),
            Span(text: "b", bold: true, italic: true),
        ])
    }

    /// snake_case must survive untouched.
    func testUnderscoresInsideWordsAreLiteral() {
        XCTAssertEqual(InlineParser.parse("some_var_name"), [Span(text: "some_var_name")])
    }

    func testUnderscoreItalicAtWordBoundary() {
        XCTAssertEqual(InlineParser.parse("_x_"), [Span(text: "x", italic: true)])
    }

    func testCodeIsLiteral() {
        XCTAssertEqual(InlineParser.parse("`**not bold**`"),
                       [Span(text: "**not bold**", code: true)])
    }

    func testLink() {
        XCTAssertEqual(InlineParser.parse("[label](https://example.com)"),
                       [Span(text: "label", link: "https://example.com")])
    }

    func testEscapedAsterisk() {
        XCTAssertEqual(InlineParser.parse("\\*literal\\*"), [Span(text: "*literal*")])
    }

    func testUnclosedBoldStaysLiteral() {
        XCTAssertEqual(InlineParser.parse("**dangling"), [Span(text: "**dangling")])
    }

    func testOpenerFollowedBySpaceIsLiteral() {
        XCTAssertEqual(InlineParser.parse("2 * 3 * 4"), [Span(text: "2 * 3 * 4")])
    }

    func testEmptyInput() {
        XCTAssertEqual(InlineParser.parse(""), [])
    }
}

/// Markdown is untrusted input. A link must not be able to hand an arbitrary
/// URL scheme to the system on a single click.
final class SafeLinkTests: XCTestCase {

    func testWebAndMailAreClickable() {
        XCTAssertNotNil(Inline.safeLink("https://example.com"))
        XCTAssertNotNil(Inline.safeLink("http://example.com"))
        XCTAssertNotNil(Inline.safeLink("mailto:someone@example.com"))
    }

    func testOtherSchemesAreNotClickable() {
        XCTAssertNil(Inline.safeLink("file:///etc/passwd"))
        XCTAssertNil(Inline.safeLink("javascript:alert(1)"))
        XCTAssertNil(Inline.safeLink("x-apple-something://do-a-thing"))
        XCTAssertNil(Inline.safeLink("ftp://example.com"))
    }

    func testSchemeMatchingIsCaseInsensitive() {
        XCTAssertNotNil(Inline.safeLink("HTTPS://example.com"))
        XCTAssertNil(Inline.safeLink("JavaScript:alert(1)"))
    }

    func testRelativeAndJunkTargetsAreNotClickable() {
        XCTAssertNil(Inline.safeLink("notes.md"))
        XCTAssertNil(Inline.safeLink(""))
    }
}
