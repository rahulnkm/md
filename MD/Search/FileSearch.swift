import Foundation

/// One file as the search sees it: its name and its whole body.
struct SearchDocument: Equatable {
    var url: URL
    var name: String
    var body: String
}

/// A ranked match. `snippet` is the line the match was found on, when it was
/// found in the body rather than the name.
struct SearchHit: Equatable {
    var url: URL
    var name: String
    var snippet: String?
    var score: Double
}

/// Ranks files against a query. Pure: documents in, hits out, no UI and no
/// disk, so the ranking is testable on its own.
///
/// Two kinds of matching, combined per file:
///
/// - **Keyword.** The query as a substring, case-insensitive, in the name or
///   any line of the body. This is what "find the note that says X" needs.
/// - **Fuzzy.** The query's characters in order but not necessarily adjacent,
///   so `mtg` finds `meeting-notes` and a typo still lands. Scored by how
///   tightly the characters cluster, so a contiguous run beats one scattered
///   across the line.
///
/// A name match outranks a body match: if you typed the file's name, that is
/// the file you meant.
enum FileSearch {

    static func search(_ rawQuery: String, in documents: [SearchDocument], limit: Int = 30) -> [SearchHit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Nothing typed yet: the list as given, which the caller orders by
        // recency, so the modal opens on the files you touched last.
        guard !query.isEmpty else {
            return documents.prefix(limit).map { SearchHit(url: $0.url, name: $0.name, snippet: nil, score: 0) }
        }

        let hits = documents.compactMap { score(query, document: $0) }
        return Array(hits
            .sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
            .prefix(limit))
    }

    // MARK: - Scoring

    private static func score(_ query: String, document: SearchDocument) -> SearchHit? {
        var total = 0.0
        var snippet: String?

        let name = document.name.lowercased()
        if name.contains(query) {
            total += name.hasPrefix(query) ? 120 : 100
        } else if let fuzzy = fuzzyScore(query, in: name), fuzzy >= 0.25 {
            total += 60 * fuzzy
        }

        var keywordCount = 0
        var bestFuzzy = 0.0
        var fuzzyLine: String?
        for line in document.body.split(separator: "\n", omittingEmptySubsequences: true) {
            let lowered = line.lowercased()
            if lowered.contains(query) {
                keywordCount += 1
                if snippet == nil { snippet = trimmed(line) }
            } else if query.count >= 3, keywordCount == 0,
                      let fuzzy = fuzzyScore(query, in: lowered), fuzzy > bestFuzzy {
                bestFuzzy = fuzzy
                fuzzyLine = trimmed(line)
            }
        }

        if keywordCount > 0 {
            total += 40 + Double(min(keywordCount, 10)) * 2
        } else if bestFuzzy >= 0.5 {
            // A fuzzy line only counts when the characters sit close together;
            // any long line contains most short queries as a scattered subsequence.
            total += 25 * bestFuzzy
            snippet = fuzzyLine
        }

        guard total > 0 else { return nil }
        return SearchHit(url: document.url, name: document.name, snippet: snippet, score: total)
    }

    /// How well `needle` appears in `haystack` as an in-order subsequence.
    ///
    /// Returns nil when it does not appear at all, otherwise 0...1 where 1 is
    /// a contiguous run. The score is the needle's length over the span it
    /// occupies, with a small bonus for starting on a word boundary, so
    /// `mn` in `meeting-notes` (m…n across the hyphen) beats `mn` buried in
    /// `harmonic`.
    static func fuzzyScore(_ needle: String, in haystack: String) -> Double? {
        let needle = Array(needle), haystack = Array(haystack)
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        // Anchor on the first needle character at each of its occurrences and
        // keep the tightest span. Greedy from a single start can miss a
        // tighter cluster later in the line.
        var best: Double?
        for start in haystack.indices where haystack[start] == needle[0] {
            var position = start + 1
            var matched = 1
            while matched < needle.count, position < haystack.count {
                if haystack[position] == needle[matched] { matched += 1 }
                position += 1
            }
            guard matched == needle.count else { break }
            let span = position - start
            var score = Double(needle.count) / Double(span)
            if start == 0 || !(haystack[start - 1].isLetter || haystack[start - 1].isNumber) {
                score = min(1, score + 0.1)
            }
            best = max(best ?? 0, score)
        }
        return best
    }

    private static func trimmed(_ line: Substring) -> String {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count > 120 ? String(text.prefix(120)) + "…" : text
    }
}
