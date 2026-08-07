import SwiftUI

/// Renders parsed blocks in Geist Sans. The editor stays monospaced - column
/// alignment matters while writing markdown - but reading does not need it, so
/// Preview switches to the proportional face. Code is the exception and keeps
/// Geist Mono wherever it appears.
struct MarkdownView: View {
    let blocks: [Block]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(Inline.attributed(text,
                                   size: Theme.headingSizes[min(level, 6) - 1],
                                   bold: true))
                .fixedSize(horizontal: false, vertical: true)
                // Headings open a section, so they get air above but not below.
                .padding(.top, level <= 2 ? 8 : 2)

        case let .paragraph(text):
            Text(Inline.attributed(text))
                .lineSpacing(Theme.proseLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

        case let .list(_, items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker)
                            .font(Theme.uiSans())
                            .foregroundColor(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(Inline.attributed(item.text))
                            .lineSpacing(Theme.proseLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 16)
                }
            }

        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 2)
                Text(Inline.attributed(text))
                    .lineSpacing(Theme.proseLineSpacing)
                    .opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .code(_, code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Theme.uiFont())
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.codeBackground)
            )

        case .rule:
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }
}

/// Turns inline spans into an `AttributedString`.
enum Inline {
    static func attributed(_ source: String,
                           size: CGFloat = Theme.proseSize,
                           bold: Bool = false) -> AttributedString {
        var out = AttributedString()
        for span in InlineParser.parse(source) {
            out.append(attributed(span, size: size, baseBold: bold))
        }
        return out
    }

    private static func attributed(_ span: Span, size: CGFloat, baseBold: Bool) -> AttributedString {
        var piece = AttributedString(span.text)
        let heavy = baseBold || span.bold

        if span.code {
            // Code keeps the monospaced face inside proportional prose, a point
            // smaller so it doesn't tower over the text around it.
            piece.font = Theme.uiFont(size: size - 1)
            piece.foregroundColor = .primary
            piece.backgroundColor = Theme.codeBackground
        } else {
            piece.font = heavy ? Theme.uiSansSemibold(size: size) : Theme.uiSans(size: size)
            // Geist ships no italic face, so italics read through opacity.
            piece.foregroundColor = span.italic ? .secondary : .primary
        }

        if let target = span.link, let url = Inline.safeLink(target) {
            piece.link = url
            piece.underlineStyle = .single
        }
        return piece
    }

    /// Only web and mail links are clickable.
    ///
    /// A markdown file is untrusted input - it can arrive from anyone. Passing
    /// its URLs straight to the system would let `[innocent text](some-app://…)`
    /// fire an arbitrary scheme handler on a single click. Anything else still
    /// renders as text, it just isn't a link.
    static func safeLink(_ target: String) -> URL? {
        guard let url = URL(string: target),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }
}
