import SwiftUI
import AppKit

/// Metrics and type carried over from Stickies' `NoteTheme`.
///
/// The colours are not. Stickies paints a fixed off-white on a fixed dark
/// scrim, which only works while something dark happens to be behind the
/// glass. Here the surface is a system `Material` and the text is a vibrant
/// system colour, so the window server resolves both against the real
/// backdrop.
enum Theme {
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

    static let codeBackground = Color.primary.opacity(0.08)

    static let blockSpacing: CGFloat = 12
    static let sidebarWidth: CGFloat = 200
    static let hairline = Color.primary.opacity(0.12)
}

/// The four surfaces, running light to dark.
///
/// Two light ones carrying dark text, two dark ones carrying white. Each
/// declares its own colour scheme rather than following the system, so the
/// choice is the user's and the pairing of surface to text can never come
/// apart - which is what made a single fixed off-white unreadable on the
/// lighter end.
enum TintStyle: String, CaseIterable {
    case mist       // lightest glass, dark text
    case smoke      // light glass, dark text
    case slate      // dark glass, white text
    case obsidian   // darkest, white text

    /// Pins the surface light or dark. Vibrant foreground styles resolve
    /// against it, so text follows the surface automatically.
    var colorScheme: ColorScheme {
        switch self {
        case .mist, .smoke:     return .light
        case .slate, .obsidian: return .dark
        }
    }

    /// The frosted layer itself.
    ///
    /// A system `Material` rather than a colour over a blur: the window server
    /// knows what is behind the glass and blends against it, which is the only
    /// way to stay legible over an unknown backdrop without asking for Screen
    /// Recording permission to go and look.
    var material: Material {
        switch self {
        case .mist:     return .ultraThinMaterial
        case .smoke:    return .thinMaterial
        case .slate:    return .regularMaterial
        case .obsidian: return .thickMaterial
        }
    }

    /// Stickies' `#2C2A33`, laid over the thickest glass so the darkest option
    /// is the original dark rather than whatever the system material happens
    /// to resolve to.
    var overlay: Color? {
        switch self {
        case .obsidian: return Color(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255).opacity(0.82)
        case .slate:    return Color(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255).opacity(0.30)
        case .mist, .smoke: return nil
        }
    }

    /// Picker circle lightness (0 = black, 1 = white). Darker note, darker swatch.
    var swatchLightness: Double {
        switch self {
        case .mist:     return 0.97
        case .smoke:    return 0.78
        case .slate:    return 0.34
        case .obsidian: return 0.11
        }
    }
}
