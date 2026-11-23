import SwiftUI
import UIKit

/// "Intaglio Pulse" tokens. Ink depth (h0–h4) encodes training volume; rose is reserved
/// for PRs, the live moment and the single primary action on a screen.
enum Theme {
    // MARK: Surfaces & text
    static let paper = Color(light: 0xEEF1EC, dark: 0x0E1614)
    static let card = Color(light: 0xF9FBF8, dark: 0x16211E)
    static let sunk = Color(light: 0xE2E8E2, dark: 0x0A110F)
    static let ink = Color(light: 0x13221F, dark: 0xE2E9E4)
    static let soft = Color(light: 0x52625E, dark: 0x9BAAA4)
    static let rule = Color(light: 0xC9D2CC, dark: 0x2A3833)

    // MARK: Signal inks
    static let rose = Color(light: 0xA61E63, dark: 0xF2689F)
    static let intaglio = Color(light: 0x2A4896, dark: 0x8EA6F2)

    // MARK: Volume ramp, rest → peak. In dark mode more volume is brighter.
    static let volume: [Color] = [
        Color(light: 0xDDE3DD, dark: 0x1C2825),
        Color(light: 0xC3CDE6, dark: 0x1F2C4F),
        Color(light: 0x8FA2D6, dark: 0x2F4687),
        Color(light: 0x4F68B5, dark: 0x5170C9),
        Color(light: 0x1F3A85, dark: 0x9DB3F5),
    ]

    static func volume(_ level: VolumeLevel) -> Color { volume[level.rawValue] }

    // MARK: Type (all scale with Dynamic Type)
    /// Denomination numeral: the one number that matters on a screen. Archivo 900 at 125% width.
    static func denomination(_ size: CGFloat = 44) -> Font {
        Typeface.display.font(size: size, weight: 900, width: 125, relativeTo: .largeTitle, maxScale: 1.5)
    }
    /// Screen and card titles. Archivo 800 at 118% width.
    static func title(_ size: CGFloat = 22) -> Font {
        Typeface.display.font(size: size, weight: 800, width: 118, relativeTo: .title2, maxScale: 1.6)
    }
    /// Section headings. Archivo 700 at 112% width.
    static func heading(_ size: CGFloat = 15) -> Font {
        Typeface.display.font(size: size, weight: 700, width: 112, relativeTo: .headline)
    }
    /// Running text. Atkinson Hyperlegible Next.
    static func text(_ size: CGFloat = 15, weight: CGFloat = 400) -> Font {
        Typeface.text.font(size: size, weight: weight, relativeTo: .body)
    }
    /// Readings and facts. Atkinson Hyperlegible Mono.
    static func data(_ size: CGFloat = 12, weight: CGFloat = 400) -> Font {
        Typeface.mono.font(size: size, weight: weight, relativeTo: .footnote)
    }
    /// Uppercase eyebrows and grid labels. Atkinson Hyperlegible Mono 500.
    static func label(_ size: CGFloat = 10.5) -> Font {
        Typeface.mono.font(size: size, weight: 500, relativeTo: .caption2, maxScale: 1.6)
    }
    /// Month and weekday labels on the grid. Fixed size: they must stay aligned with 11 pt cells.
    static var gridLabel: Font {
        Typeface.mono.font(size: 8.5, weight: 500, relativeTo: .caption2, maxScale: 1)
    }

    // MARK: Heatmap geometry
    static let cellSize: CGFloat = 11
    static let cellGap: CGFloat = 3
    static let cellRadius: CGFloat = 2.5
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
