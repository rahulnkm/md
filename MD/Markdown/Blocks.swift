import Foundation

/// One item in a bullet or ordered list.
struct ListItem: Equatable {
    /// The rendered marker, e.g. "-" or "3.".
    var marker: String
    /// Item text, still containing inline markup.
    var text: String
    /// Nesting depth, derived from leading whitespace. Capped at 3.
    var indent: Int
}

/// A block-level element. Inline markup inside `text` is left intact and
/// resolved later by `Inline.render`.
enum Block: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [ListItem])
    case quote(String)
    case code(language: String?, code: String)
    case rule
}

/// Line-based block parser. Pure: string in, blocks out, no UI types.
///
/// Deliberately covers the subset a notes app actually produces. Tables,
/// footnotes, HTML passthrough, and setext headings fall through to
/// paragraphs rather than breaking.
enum MarkdownParser {

    static func parse(_ source: String) -> [Block] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [Block] = []
        var paragraph: [(text: String, hardBreak: Bool)] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(join(paragraph)))
            paragraph.removeAll()
        }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code. Consumes until a matching closing fence or EOF, so
            // an unclosed fence yields one code block rather than swallowing
            // the parser.
            if let fenceChar = openingFence(line) {
                flushParagraph()
                let language = String(line.drop(while: { $0 == fenceChar }))
                    .trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if isClosingFence(candidate, fenceChar) { i += 1; break }
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language,
                                    code: body.joined(separator: "\n")))
                continue
            }

            if line.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if isRule(line) {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            if isQuote(line) {
                flushParagraph()
                var body: [(text: String, hardBreak: Bool)] = []
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isQuote(candidate) else { break }
                    body.append(prose(stripQuoteMarker(candidate)))
                    i += 1
                }
                blocks.append(.quote(join(body)))
                continue
            }

            if bulletMarker(line) != nil || orderedMarker(line) != nil {
                flushParagraph()
                let ordered = orderedMarker(line) != nil
                var items: [ListItem] = []
                while i < lines.count {
                    let rawLine = lines[i]
                    let candidate = rawLine.trimmingCharacters(in: .whitespaces)
                    let indent = min(3, leadingSpaces(rawLine) / 2)

                    if !ordered, let marker = bulletMarker(candidate) {
                        items.append(ListItem(marker: "-",
                                              text: String(candidate.dropFirst(marker.count))
                                                .trimmingCharacters(in: .whitespaces),
                                              indent: indent))
                    } else if ordered, let marker = orderedMarker(candidate) {
                        items.append(ListItem(marker: marker.trimmingCharacters(in: .whitespaces),
                                              text: String(candidate.dropFirst(marker.count))
                                                .trimmingCharacters(in: .whitespaces),
                                              indent: indent))
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.list(ordered: ordered, items: items))
                continue
            }

            paragraph.append(prose(raw))
            i += 1
        }

        flushParagraph()
        return blocks
    }

    // MARK: - Soft wrapping

    /// Classifies one line of prose.
    ///
    /// A single newline inside a paragraph is a soft wrap: the author wrapped
    /// their source, they did not ask for a line break. Joining is what
    /// CommonMark does and what makes hard-wrapped files read as flowing
    /// paragraphs. A deliberate break is still available the standard two
    /// ways - end the line with two spaces, or with a backslash.
    private static func prose(_ raw: String) -> (text: String, hardBreak: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("\\") {
            return (String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces), true)
        }
        return (trimmed, raw.hasSuffix("  "))
    }

    private static func join(_ lines: [(text: String, hardBreak: Bool)]) -> String {
        var out = ""
        for (index, line) in lines.enumerated() {
            out += line.text
            guard index < lines.count - 1 else { continue }
            out += line.hardBreak ? "\n" : " "
        }
        return out
    }

    // MARK: - Line classification

    /// Returns the fence character if the line opens a fenced code block.
    private static func openingFence(_ line: String) -> Character? {
        for char in ["`", "~"] as [Character] {
            if line.prefix(3).allSatisfy({ $0 == char }) && line.count >= 3 { return char }
        }
        return nil
    }

    /// A closing fence is a run of three or more of the same fence character
    /// and nothing else.
    private static func isClosingFence(_ line: String, _ char: Character) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == char }
    }

    /// Three or more of `-`, `*`, or `_`, all the same, nothing else.
    /// Checked before list markers so `---` is a rule and `- x` is a bullet.
    private static func isRule(_ line: String) -> Bool {
        let stripped = line.filter { $0 != " " }
        guard stripped.count >= 3, let first = stripped.first,
              "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = String(line.dropFirst(hashes.count))
        // ATX headings require a space after the hashes, so `#tag` stays prose.
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return .heading(level: hashes.count, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isQuote(_ line: String) -> Bool { line.hasPrefix(">") }

    private static func stripQuoteMarker(_ line: String) -> String {
        var rest = line.drop(while: { $0 == ">" })
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        return String(rest)
    }

    /// Returns the literal marker text, e.g. "- ", if the line opens a bullet.
    private static func bulletMarker(_ line: String) -> String? {
        guard let first = line.first, "-*+".contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.hasPrefix(" ") else { return nil }
        return String(line.prefix(1)) + " "
    }

    /// Returns the literal marker text, e.g. "12. ", if the line opens an
    /// ordered item.
    private static func orderedMarker(_ line: String) -> String? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return String(digits) + ". "
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " { count += 1 }
            else if char == "\t" { count += 4 }
            else { break }
        }
        return count
    }
}
