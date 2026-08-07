import XCTest
@testable import MD

/// The window is translucent, so what sits behind the text is the desktop.
/// These check the worst case - the tint painted over a pure white desktop -
/// because that is the only contrast the app can actually promise.
final class ContrastTests: XCTestCase {

    /// Every text level, at every tint, clears WCAG AA for body text.
    func testEveryTextLevelClearsAAAtEveryTint() {
        let levels: [(String, CGFloat)] = [
            ("primary", Theme.primaryTextOpacity),
            ("secondary", Theme.secondaryTextOpacity),
            ("tertiary", Theme.tertiaryTextOpacity),
            ("syntax", Theme.syntaxOpacity),
            ("italic", Theme.italicOpacity),
        ]

        for tint in TintStyle.allCases {
            for (name, opacity) in levels {
                let ratio = Theme.worstCaseRatio(textOpacity: opacity, tint: tint)
                XCTAssertGreaterThanOrEqual(
                    ratio, Contrast.aa,
                    "\(name) text on \(tint.rawValue) is \(String(format: "%.2f", ratio)):1, " +
                    "under the \(Contrast.aa):1 floor"
                )
            }
        }
    }

    /// No text level may sit below the documented floor.
    func testNoTextLevelIsBelowTheFloor() {
        for opacity in [Theme.primaryTextOpacity, Theme.secondaryTextOpacity,
                        Theme.tertiaryTextOpacity, Theme.syntaxOpacity,
                        Theme.italicOpacity] {
            XCTAssertGreaterThanOrEqual(opacity, Theme.minimumTextOpacity)
        }
    }

    /// The lightest tint has to stay above the point where body text fails.
    /// Stickies' own values (0.00 / 0.08 / 0.18 / 0.38) all sit below it.
    func testLightestTintIsAboveTheLegibilityFloor() {
        let lightest = TintStyle.allCases.map(\.tintOpacity).min()!
        XCTAssertGreaterThanOrEqual(lightest, 0.725,
                                    "body text stops clearing AA below this scrim alpha")
    }

    func testTintsAreOrderedLightToDark() {
        let opacities = TintStyle.allCases.map(\.tintOpacity)
        XCTAssertEqual(opacities, opacities.sorted(), "mist through obsidian must increase")
    }

    // MARK: - The maths itself

    func testKnownLuminances() {
        XCTAssertEqual(Contrast.luminance(Contrast.white), 1.0, accuracy: 0.001)
        XCTAssertEqual(Contrast.luminance(.hex(0x000000)), 0.0, accuracy: 0.001)
    }

    /// Black on white is the reference maximum, 21:1.
    func testBlackOnWhiteIsTwentyOne() {
        XCTAssertEqual(Contrast.ratio(.hex(0x000000), Contrast.white), 21.0, accuracy: 0.01)
    }

    func testRatioIsSymmetric() {
        let a = Contrast.RGB.hex(0xE8E3D8)
        let b = Contrast.RGB.hex(0x2C2A33)
        XCTAssertEqual(Contrast.ratio(a, b), Contrast.ratio(b, a), accuracy: 0.0001)
    }

    func testSameColourHasNoContrast() {
        let colour = Contrast.RGB.hex(0x2C2A33)
        XCTAssertEqual(Contrast.ratio(colour, colour), 1.0, accuracy: 0.0001)
    }

    func testAlphaCompositing() {
        let black = Contrast.RGB.hex(0x000000)
        XCTAssertEqual(black.over(Contrast.white, alpha: 0), Contrast.white)
        XCTAssertEqual(black.over(Contrast.white, alpha: 1), black)
        XCTAssertEqual(black.over(Contrast.white, alpha: 0.5),
                       Contrast.RGB(r: 127.5, g: 127.5, b: 127.5))
    }

    /// Full-strength text on the fully opaque tint, with no desktop showing
    /// through at all. This is the best the palette ever gets.
    func testOpaqueTintIsComfortablyAbove() {
        let ratio = Theme.worstCaseRatio(textOpacity: 1.0, tint: .obsidian)
        XCTAssertGreaterThan(ratio, 10.0)
    }
}
