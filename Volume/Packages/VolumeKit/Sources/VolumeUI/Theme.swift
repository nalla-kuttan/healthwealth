import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// "Intaglio Pulse" design tokens. Ink depth (`volume`) encodes training volume; rose is reserved
/// for PRs, the live moment and the single primary action on a screen. Recovery semantics
/// (`ok`/`warn`/`crit`) never appear on the heatmap.
public enum Theme {
    // MARK: Surfaces & text
    public static let paper = Color(light: 0xEEF1EC, dark: 0x0E1614)
    public static let card = Color(light: 0xF9FBF8, dark: 0x16211E)
    public static let sunk = Color(light: 0xE2E8E2, dark: 0x0A110F)
    public static let ink = Color(light: 0x13221F, dark: 0xE2E9E4)
    public static let soft = Color(light: 0x52625E, dark: 0x9BAAA4)
    public static let rule = Color(light: 0xC9D2CC, dark: 0x2A3833)

    // MARK: Signal inks
    public static let rose = Color(light: 0xA61E63, dark: 0xF2689F)
    public static let intaglio = Color(light: 0x2A4896, dark: 0x8EA6F2)
    /// Text on a rose fill.
    public static let onRose = Color(light: 0xFFFFFF, dark: 0x0E1614)

    // MARK: Recovery semantics (PRD 4.3), always paired with a word and a mark
    public static let ok = Color(light: 0x286B43, dark: 0x6CCB92)
    public static let warn = Color(light: 0x975A00, dark: 0xE3A548)
    public static let crit = Color(light: 0xB3261E, dark: 0xF08A80)

    // MARK: Volume ramp, rest → peak. In dark mode more volume is brighter.
    public static let volume: [Color] = [
        Color(light: 0xDDE3DD, dark: 0x1C2825),
        Color(light: 0xC3CDE6, dark: 0x1F2C4F),
        Color(light: 0x8FA2D6, dark: 0x2F4687),
        Color(light: 0x4F68B5, dark: 0x5170C9),
        Color(light: 0x1F3A85, dark: 0x9DB3F5),
    ]

    public static func volume(level: Int) -> Color { volume[min(max(level, 0), volume.count - 1)] }

    // MARK: Type (scales with Dynamic Type)
    /// Denomination numeral: the one number that matters on a screen. Archivo 900, 125% width.
    public static func denomination(_ size: CGFloat = 44) -> Font {
        Typeface.display.font(size: size, weight: 900, width: 125, relativeTo: .largeTitle, maxScale: 1.5)
    }
    /// Screen and card titles. Archivo 800, 118% width.
    public static func title(_ size: CGFloat = 22) -> Font {
        Typeface.display.font(size: size, weight: 800, width: 118, relativeTo: .title2, maxScale: 1.6)
    }
    /// Section headings. Archivo 700, 112% width.
    public static func heading(_ size: CGFloat = 16) -> Font {
        Typeface.display.font(size: size, weight: 700, width: 112, relativeTo: .headline)
    }
    /// Running text. Atkinson Hyperlegible Next.
    public static func text(_ size: CGFloat = 15, weight: CGFloat = 400) -> Font {
        Typeface.text.font(size: size, weight: weight, relativeTo: .body)
    }
    /// Readings and facts. Atkinson Hyperlegible Mono.
    public static func data(_ size: CGFloat = 12, weight: CGFloat = 400) -> Font {
        Typeface.mono.font(size: size, weight: weight, relativeTo: .footnote)
    }
    /// Uppercase eyebrows. Atkinson Hyperlegible Mono 500.
    public static func label(_ size: CGFloat = 10.5) -> Font {
        Typeface.mono.font(size: size, weight: 500, relativeTo: .caption2, maxScale: 1.6)
    }
    /// Month and weekday labels on the grid. Fixed so they stay aligned with the cells.
    public static func gridLabel(_ size: CGFloat = 9) -> Font {
        Typeface.mono.font(size: size, weight: 500, relativeTo: .caption2, maxScale: 1)
    }
}

/// Bundled variable fonts (SIL Open Font License; licences ship in Resources/Fonts).
/// - Archivo: display and headings, using its width axis for the expanded look.
/// - Atkinson Hyperlegible Next: running text, designed for low-vision readers.
/// - Atkinson Hyperlegible Mono: data, dates and labels.
public enum Typeface: CaseIterable, Sendable {
    case display, text, mono

    /// Any named instance works as the base; weight and width come from the variation axes.
    var postScriptName: String {
        switch self {
        case .display: "ArchivoRoman-Regular"
        case .text: "AtkinsonHyperlegibleNext-Regular"
        case .mono: "AtkinsonHyperlegibleMono-ExtraLight_Regular"
        }
    }

    private var familyPrefix: String { self == .display ? "Archivo" : "Atkinson" }

    private var weightRange: ClosedRange<CGFloat> { self == .display ? 100...900 : 200...800 }

    private static let weightAxis = NSNumber(value: 0x7767_6874) // 'wght'
    private static let widthAxis = NSNumber(value: 0x7764_7468)  // 'wdth'

    #if canImport(UIKit)
    /// A Dynamic Type–scaled font with explicit variation values.
    /// - Parameters:
    ///   - weight: CSS-style weight, e.g. 400 regular, 700 bold, 900 black.
    ///   - width: percent of normal width (Archivo supports 62–125).
    public func font(size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100,
                     relativeTo style: UIFont.TextStyle = .body, maxScale: CGFloat = 2) -> Font {
        Font(uiFont(size: size, weight: weight, width: width, relativeTo: style, maxScale: maxScale))
    }

    public func uiFont(size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100,
                       relativeTo style: UIFont.TextStyle = .body, maxScale: CGFloat = 2) -> UIFont {
        _ = FontRegistry.registered
        let clamped = min(max(weight, weightRange.lowerBound), weightRange.upperBound)
        var variations: [NSNumber: CGFloat] = [Self.weightAxis: clamped]
        if self == .display { variations[Self.widthAxis] = min(max(width, 62), 125) }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: postScriptName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
        ])
        var base = UIFont(descriptor: descriptor, size: size)
        if !base.familyName.hasPrefix(familyPrefix) { base = fallback(size: size, weight: clamped) }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: size * maxScale)
    }

    private func fallback(size: CGFloat, weight: CGFloat) -> UIFont {
        let systemWeight: UIFont.Weight = switch weight {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
        let system = UIFont.systemFont(ofSize: size, weight: systemWeight)
        guard self == .mono, let mono = system.fontDescriptor.withDesign(.monospaced) else { return system }
        return UIFont(descriptor: mono, size: size)
    }
    #else
    /// macOS (`swift test`) builds compile the UI but never ship it: system fonts stand in.
    public func font(size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100,
                     relativeTo style: Font.TextStyle = .body, maxScale: CGFloat = 2) -> Font {
        .system(size: size, weight: weight >= 650 ? .bold : .regular, design: self == .mono ? .monospaced : .default)
    }
    #endif
}

public enum FontRegistry {
    /// Registers the bundled fonts once per process (app, widget extension, previews), the first
    /// time any themed font is built.
    public static let registered: Bool = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls {
            var error: Unmanaged<CFError>?
            // Failure means already registered or unreadable; either way text falls back cleanly.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { error?.release() }
        }
        return !urls.isEmpty
    }()
}

#if canImport(UIKit)
public extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
public extension Color {
    /// macOS (`swift test`) builds: light values only; the UI targets iOS.
    init(light: UInt32, dark: UInt32) {
        self.init(.sRGB, red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255,
                  blue: Double(light & 0xFF) / 255)
    }
}
#endif

/// The double-ring PR mark, like a struck medal.
public struct MedalMark: View {
    var size: CGFloat
    public init(size: CGFloat = 14) { self.size = size }

    public var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.rose, lineWidth: max(1.2, size * 0.1))
            Circle().strokeBorder(Theme.rose, lineWidth: max(1.2, size * 0.1)).padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Paper card with a 1 pt rule: depth comes from the rule, not a shadow.
public struct PaperCard: ViewModifier {
    var padding: CGFloat
    public init(padding: CGFloat = 16) { self.padding = padding }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.rule))
    }
}

public extension View {
    func paperCard(padding: CGFloat = 16) -> some View { modifier(PaperCard(padding: padding)) }
}
