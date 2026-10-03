import XCTest
import DesignSystem

final class EngramThemeTests: XCTestCase {
    func testSemanticInkMeetsTextContrastAcrossEveryThemeAndAppearance() {
        for theme in EngramTheme.allCases {
            for dark in [false, true] {
                let tokens = theme.colors(dark: dark)
                XCTAssertGreaterThanOrEqual(contrast(tokens.primaryText, tokens.canvas), 4.5, "\(theme.rawValue) primary text / canvas (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.secondaryText, tokens.canvas), 4.5, "\(theme.rawValue) secondary text / canvas (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.answerSelectionInk, tokens.canvas), 4.5, "\(theme.rawValue) selection ink / canvas (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.answerSelectionInk, tokens.surface), 4.5, "\(theme.rawValue) selection ink / surface (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.successInk, tokens.canvas), 4.5, "\(theme.rawValue) success ink / canvas (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.successInk, tokens.surface), 4.5, "\(theme.rawValue) success ink / surface (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.missingInk, tokens.canvas), 4.5, "\(theme.rawValue) missing ink / canvas (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.missingInk, tokens.surface), 4.5, "\(theme.rawValue) missing ink / surface (dark: \(dark))")
                XCTAssertGreaterThanOrEqual(contrast(tokens.onAnchor, tokens.anchor), 4.5, "\(theme.rawValue) anchor pair (dark: \(dark))")
            }
        }
    }

    func testMonochromeUsesPureWhiteAndBlackCanvases() {
        XCTAssertEqual(EngramTheme.monochrome.colors(dark: false).canvas, 0xFFFFFF)
        XCTAssertEqual(EngramTheme.monochrome.colors(dark: true).canvas, 0x000000)
    }

    private func contrast(_ foreground: UInt32, _ background: UInt32) -> Double {
        func luminance(_ color: UInt32) -> Double {
            let components = [16, 8, 0].map { shift -> Double in
                let value = Double((color >> shift) & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
        }
        let first = luminance(foreground), second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
