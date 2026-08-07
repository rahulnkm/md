import Foundation
import CoreGraphics

/// WCAG 2.1 relative luminance and contrast ratios, in sRGB.
///
/// Pure arithmetic with no UI types, so the whole palette can be checked by
/// tests instead of eyeballed. This matters more here than in an opaque app:
/// the window is translucent, so what sits behind the text is the desktop,
/// and the only contrast that can be guaranteed is the worst case.
enum Contrast {

    struct RGB: Equatable {
        /// Channels in 0...255.
        var r: Double
        var g: Double
        var b: Double

        static func hex(_ value: UInt32) -> RGB {
            RGB(r: Double((value >> 16) & 0xFF),
                g: Double((value >> 8) & 0xFF),
                b: Double(value & 0xFF))
        }

        /// This colour painted over `background` at `alpha`.
        func over(_ background: RGB, alpha: Double) -> RGB {
            let a = min(max(alpha, 0), 1)
            return RGB(r: r * a + background.r * (1 - a),
                       g: g * a + background.g * (1 - a),
                       b: b * a + background.b * (1 - a))
        }
    }

    /// The brightest thing that can ever sit behind the window.
    static let white = RGB(r: 255, g: 255, b: 255)

    static func luminance(_ colour: RGB) -> Double {
        func linear(_ value: Double) -> Double {
            let s = value / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.r)
             + 0.7152 * linear(colour.g)
             + 0.0722 * linear(colour.b)
    }

    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG AA for body text. Large text is allowed 3.0, but everything here
    /// is held to the stricter number rather than sorting text by point size.
    static let aa = 4.5
}
