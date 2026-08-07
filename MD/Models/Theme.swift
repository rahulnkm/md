import SwiftUI
import AppKit

/// Carried over from Stickies' `NoteTheme` so the two apps read as siblings.
/// Values above the `Markdown` mark are unchanged from that repo.
enum Theme {
    static let bg = Color(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255)
    static let text = Color(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255)
    static let nsBg = NSColor(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255, alpha: 1)
    static let nsText = NSColor(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255, alpha: 1)
    static let cornerRadius: CGFloat = 6
    static let innerPadding: CGFloat = 16
    static let topPadding: CGFloat = 30   // room so hover-reveal chrome doesn't collide with line one
    static let dotSize: CGFloat = 8
    static let dotInset: CGFloat = 12
    /// macOS yellow stoplight color (approx). Marks unsaved changes here.
    static let stoplightYellow = Color(red: 0xFE/255, green: 0xBC/255, blue: 0x2E/255)
    static let fontSize: CGFloat = 13
    static let lineHeightMultiple: CGFloat = 1.0
    static let tracking: CGFloat = 0

    /// Geist Mono, bundled via `ATSApplicationFontsPath` in Info.plist.
    /// Falls back to the system monospaced font if registration fails.
    static func font(size: CGFloat = fontSize) -> NSFont {
        NSFont(name: "GeistMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Geist Mono SemiBold. Stickies bundles Regular only; headings and bold
    /// need real weight, so this face is added here under the same OFL.
    static func semibold(size: CGFloat = fontSize) -> NSFont {
        NSFont(name: "GeistMono-SemiBold", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .semibold)
    }

    /// Geist Sans, used for rendered prose in Preview. Editing stays monospaced
    /// because column alignment matters while writing markdown; reading does
    /// not need it, and a proportional face is easier on the eye.
    static func sans(size: CGFloat = proseSize) -> NSFont {
        NSFont(name: "Geist-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    static func sansSemibold(size: CGFloat = proseSize) -> NSFont {
        NSFont(name: "Geist-SemiBold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func uiFont(size: CGFloat = fontSize) -> Font { Font(font(size: size)) }
    static func uiSemibold(size: CGFloat = fontSize) -> Font { Font(semibold(size: size)) }
    static func uiSans(size: CGFloat = proseSize) -> Font { Font(sans(size: size)) }
    static func uiSansSemibold(size: CGFloat = proseSize) -> Font { Font(sansSemibold(size: size)) }

    // MARK: - Markdown

    /// Rendered prose runs a point larger than the editor. Geist Sans sets
    /// narrower than Geist Mono, so matching point sizes would read smaller.
    static let proseSize: CGFloat = 14
    /// Extra leading under rendered prose. Proportional type needs more air
    /// than the editor's 1.0 line height.
    static let proseLineSpacing: CGFloat = 5

    /// Heading sizes for levels 1...6. Levels 4-6 share the body size and
    /// carry their weight through SemiBold alone.
    static let headingSizes: [CGFloat] = [24, 19, 16, 14, 14, 14]

    static let codeBackground = text.opacity(0.06)
    static let nsCodeBackground = NSColor(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255, alpha: 0.06)
    /// Markdown syntax characters recede to this opacity while editing.
    static let syntaxOpacity: CGFloat = 0.4
    static let nsSyntax = NSColor(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255, alpha: syntaxOpacity)
    /// Geist Mono has no italic face; italics carry through opacity instead.
    static let italicOpacity: CGFloat = 0.72

    static let blockSpacing: CGFloat = 12
    static let sidebarWidth: CGFloat = 200
    static let hairline = text.opacity(0.08)
}

/// How much the dark palette tints the frosted-glass background.
/// Same four styles and opacities as Stickies.
enum TintStyle: String, CaseIterable {
    case mist       // lightest - barely tinted
    case smoke      // light frosted
    case slate      // default - balanced dark
    case obsidian   // darkest - near-opaque

    var tintOpacity: Double {
        switch self {
        case .mist:     return 0.00
        case .smoke:    return 0.08
        case .slate:    return 0.18
        case .obsidian: return 0.38
        }
    }

    /// Picker circle lightness (0 = black, 1 = white). Darker note, darker swatch.
    var swatchLightness: Double {
        switch self {
        case .mist:     return 0.92
        case .smoke:    return 0.70
        case .slate:    return 0.35
        case .obsidian: return 0.15
        }
    }
}
