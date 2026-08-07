import Foundation

/// A run of text sharing one set of inline styles.
struct Span: Equatable {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: String?
}

/// Inline markup scanner. Pure: string in, spans out, no UI types, so the
/// tricky part (delimiter matching) is testable without a running app.
///
/// Handles `**bold**`, `*italic*`, `_italic_`, `` `code` ``, `[label](url)`,
/// and `\` escapes. Bold and italic nest; code does not - its contents are
/// literal, as in CommonMark.
enum InlineParser {

    static func parse(_ source: String) -> [Span] {
        var spans: [Span] = []
        let chars = Array(source)
        scan(chars, 0, chars.count, Style(), into: &spans)
        return merge(spans)
    }

    private struct Style {
        var bold = false
        var italic = false
        var link: String?
    }

    private static func scan(_ c: [Character], _ start: Int, _ end: Int,
                             _ style: Style, into out: inout [Span]) {
        var buffer = ""
        var i = start

        func flush() {
            guard !buffer.isEmpty else { return }
            out.append(Span(text: buffer, bold: style.bold, italic: style.italic,
                            code: false, link: style.link))
            buffer = ""
        }

        while i < end {
            let char = c[i]

            if char == "\\", i + 1 < end {
                buffer.append(c[i + 1])
                i += 2
                continue
            }

            if char == "`", let close = findLiteral(c, i + 1, end, "`") {
                flush()
                out.append(Span(text: String(c[(i + 1)..<close]), code: true, link: style.link))
                i = close + 1
                continue
            }

            if char == "*", i + 1 < end, c[i + 1] == "*",
               let close = findDouble(c, i + 2, end, "*") {
                flush()
                var inner = style
                inner.bold = true
                scan(c, i + 2, close, inner, into: &out)
                i = close + 2
                continue
            }

            if char == "*" || char == "_",
               isEmphasisOpener(c, i, end),
               let close = findEmphasisClose(c, i + 1, end, char) {
                flush()
                var inner = style
                inner.italic = true
                scan(c, i + 1, close, inner, into: &out)
                i = close + 1
                continue
            }

            if char == "[",
               let bracket = find(c, i + 1, end, "]"),
               bracket + 1 < end, c[bracket + 1] == "(",
               let paren = find(c, bracket + 2, end, ")") {
                flush()
                var inner = style
                inner.link = String(c[(bracket + 2)..<paren])
                scan(c, i + 1, bracket, inner, into: &out)
                i = paren + 1
                continue
            }

            buffer.append(char)
            i += 1
        }

        flush()
    }

    // MARK: - Delimiter matching

    private static func find(_ c: [Character], _ from: Int, _ end: Int,
                             _ target: Character) -> Int? {
        var i = from
        while i < end {
            if c[i] == "\\" { i += 2; continue }
            if c[i] == target { return i }
            i += 1
        }
        return nil
    }

    /// Backtick spans take their contents literally, so escapes are not honoured.
    private static func findLiteral(_ c: [Character], _ from: Int, _ end: Int,
                                    _ target: Character) -> Int? {
        var i = from
        while i < end {
            if c[i] == target { return i }
            i += 1
        }
        return nil
    }

    /// Finds the closing `**`.
    ///
    /// When the closing run is longer than two - `***both***` - the bold pair
    /// is the *last* two characters of the run, leaving the first to close an
    /// inner italic. Returning the first two instead strands the extra marker
    /// as literal text.
    private static func findDouble(_ c: [Character], _ from: Int, _ end: Int,
                                   _ marker: Character) -> Int? {
        var i = from
        while i + 1 < end {
            if c[i] == "\\" { i += 2; continue }
            if c[i] == marker, c[i + 1] == marker {
                var runEnd = i
                while runEnd < end, c[runEnd] == marker { runEnd += 1 }
                return runEnd - 2
            }
            i += 1
        }
        return nil
    }

    /// An opener needs non-space immediately after it. Underscores additionally
    /// must not sit inside a word, so `snake_case_names` stay upright.
    private static func isEmphasisOpener(_ c: [Character], _ i: Int, _ end: Int) -> Bool {
        guard i + 1 < end, !c[i + 1].isWhitespace else { return false }
        if c[i] == "_", i > 0, c[i - 1].isLetter || c[i - 1].isNumber { return false }
        return true
    }

    /// A closer needs non-space immediately before it, and for underscores,
    /// a non-word character after it.
    private static func findEmphasisClose(_ c: [Character], _ from: Int, _ end: Int,
                                          _ marker: Character) -> Int? {
        var i = from
        while i < end {
            if c[i] == "\\" { i += 2; continue }
            if c[i] == marker, i > from, !c[i - 1].isWhitespace {
                if marker == "_", i + 1 < end, c[i + 1].isLetter || c[i + 1].isNumber {
                    i += 1
                    continue
                }
                return i
            }
            i += 1
        }
        return nil
    }

    /// Collapses adjacent runs that share styling, so output is stable and
    /// comparable in tests.
    private static func merge(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for span in spans where !span.text.isEmpty {
            if var last = out.last,
               last.bold == span.bold, last.italic == span.italic,
               last.code == span.code, last.link == span.link {
                last.text += span.text
                out[out.count - 1] = last
            } else {
                out.append(span)
            }
        }
        return out
    }
}
