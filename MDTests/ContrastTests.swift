import XCTest
@testable import MD

/// Contrast here is a deliberate trade, so these record what is actually
/// promised rather than pretending the whole palette clears WCAG AA.
///
/// The window is glass. What sits behind the text is the desktop, and it can
/// be any colour, so no translucent tint can guarantee a ratio. The app buys
/// legibility with a per-glyph shadow instead - which WCAG has no way to score
/// - and keeps the frosted look. The tests below pin down the parts that
/// *can* be checked: the opaque end of the range, the text-opacity floor, and
/// the shadow being present and strongest where it is needed most.
final class ContrastTests: XCTestCase {

    // MARK: - What is guaranteed

    /// With the darkest tint over the darkest desktop, every text level clears
    /// AA comfortably. This is the floor of the *good* case, and it is the one
    /// the palette is tuned against.
    func testEveryTextLevelClearsAAOnADarkDesktop() {
        let darkDesktop = Contrast.RGB.hex(0x1E1E1E)

        for tint in TintStyle.allCases {
            let background = Contrast.RGB.hex(Theme.backgroundHex)
                .over(darkDesktop, alpha: tint.tintOpacity)
            for (name, opacity) in Self.textLevels {
                let foreground = Contrast.RGB.hex(Theme.textHex)
                    .over(background, alpha: Double(opacity))
                let ratio = Contrast.ratio(foreground, background)
                XCTAssertGreaterThanOrEqual(
                    ratio, Contrast.aa,
                    "\(name) on \(tint.rawValue) is \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }

    /// No text level may drop below the floor. Dates at 0.45 and syntax at
    /// 0.40 used to fail even against a fully opaque background.
    func testNoTextLevelIsBelowTheFloor() {
        for (name, opacity) in Self.textLevels {
            XCTAssertGreaterThanOrEqual(opacity, Theme.minimumTextOpacity,
                                        "\(name) is under the floor")
        }
    }

    // MARK: - The shadow that replaces an opaque background

    /// Every tint carries a halo. A tint with none would be unreadable the
    /// moment the window sat over anything bright.
    func testEveryTintHasAShadow() {
        for tint in TintStyle.allCases {
            XCTAssertGreaterThan(tint.shadowStrength, 0.5,
                                 "\(tint.rawValue) has no meaningful halo")
            XCTAssertLessThanOrEqual(tint.shadowStrength, 1.0)
        }
    }

    /// The less the window darkens what is behind it, the harder the halo has
    /// to work.
    func testShadowGrowsAsTheTintThins() {
        let byTint = TintStyle.allCases.sorted { $0.tintOpacity < $1.tintOpacity }
        let strengths = byTint.map(\.shadowStrength)
        XCTAssertEqual(strengths, strengths.sorted(by: >),
                       "lighter tints must carry darker halos")
    }

    func testTintsAreOrderedLightToDark() {
        let opacities = TintStyle.allCases.map(\.tintOpacity)
        XCTAssertEqual(opacities, opacities.sorted())
    }

    /// Recorded so the trade is visible rather than forgotten: against a white
    /// desktop the translucent tints do not reach AA on their own. That is the
    /// cost of the glass, and the halo is what covers it.
    func testTranslucentTintsDoNotClearAAOnWhiteAlone() {
        let ratio = Theme.worstCaseRatio(textOpacity: 1.0, tint: .mist)
        XCTAssertLessThan(ratio, Contrast.aa,
                          "if this ever passes, the tint stopped being glass")
    }

    // MARK: - The maths itself

    func testKnownLuminances() {
        XCTAssertEqual(Contrast.luminance(Contrast.white), 1.0, accuracy: 0.001)
        XCTAssertEqual(Contrast.luminance(.hex(0x000000)), 0.0, accuracy: 0.001)
    }

    func testBlackOnWhiteIsTwentyOne() {
        XCTAssertEqual(Contrast.ratio(.hex(0x000000), Contrast.white), 21.0, accuracy: 0.01)
    }

    func testRatioIsSymmetric() {
        let a = Contrast.RGB.hex(Theme.textHex)
        let b = Contrast.RGB.hex(Theme.backgroundHex)
        XCTAssertEqual(Contrast.ratio(a, b), Contrast.ratio(b, a), accuracy: 0.0001)
    }

    func testSameColourHasNoContrast() {
        let colour = Contrast.RGB.hex(Theme.backgroundHex)
        XCTAssertEqual(Contrast.ratio(colour, colour), 1.0, accuracy: 0.0001)
    }

    func testAlphaCompositing() {
        let black = Contrast.RGB.hex(0x000000)
        XCTAssertEqual(black.over(Contrast.white, alpha: 0), Contrast.white)
        XCTAssertEqual(black.over(Contrast.white, alpha: 1), black)
        XCTAssertEqual(black.over(Contrast.white, alpha: 0.5),
                       Contrast.RGB(r: 127.5, g: 127.5, b: 127.5))
    }

    private static let textLevels: [(String, CGFloat)] = [
        ("primary", Theme.primaryTextOpacity),
        ("secondary", Theme.secondaryTextOpacity),
        ("tertiary", Theme.tertiaryTextOpacity),
        ("syntax", Theme.syntaxOpacity),
        ("italic", Theme.italicOpacity),
    ]
}
