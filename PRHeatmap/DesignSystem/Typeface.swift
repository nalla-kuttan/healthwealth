import CoreText
import SwiftUI
import UIKit

/// Bundled variable fonts (SIL Open Font License, licences in Resources/Fonts).
/// - Archivo: display and headings, using its width axis for the expanded "denomination" look.
/// - Atkinson Hyperlegible Next: running text, designed for low-vision readers.
/// - Atkinson Hyperlegible Mono: data, dates and labels.
enum Typeface: CaseIterable {
    case display, text, mono

    /// Any named instance works as the base; weight and width come from the variation axes.
    var postScriptName: String {
        switch self {
        case .display: "ArchivoRoman-Regular"
        case .text: "AtkinsonHyperlegibleNext-Regular"
        case .mono: "AtkinsonHyperlegibleMono-ExtraLight_Regular"
        }
    }

    var weightRange: ClosedRange<CGFloat> {
        switch self {
        case .display: 100...900
        case .text, .mono: 200...800
        }
    }

    var fallbackDesign: UIFontDescriptor.SystemDesign {
        self == .mono ? .monospaced : .default
    }

    // OpenType axis tags as Core Text expects them.
    private static let weightAxis = NSNumber(value: 0x7767_6874) // 'wght'
    private static let widthAxis = NSNumber(value: 0x7764_7468)  // 'wdth'

    /// A Dynamic Type–scaled font with explicit variation values.
    /// - Parameters:
    ///   - weight: CSS-style weight, e.g. 400 regular, 700 bold, 900 black.
    ///   - width: percentage of normal width (Archivo supports 62–125).
    func font(size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100,
              relativeTo style: UIFont.TextStyle = .body, maxScale: CGFloat = 2) -> Font {
        Font(uiFont(size: size, weight: weight, width: width, relativeTo: style, maxScale: maxScale))
    }

    func uiFont(size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100,
                relativeTo style: UIFont.TextStyle = .body, maxScale: CGFloat = 2) -> UIFont {
        _ = FontRegistry.registered
        let clampedWeight = min(max(weight, weightRange.lowerBound), weightRange.upperBound)
        var variations: [NSNumber: CGFloat] = [Self.weightAxis: clampedWeight]
        if self == .display { variations[Self.widthAxis] = min(max(width, 62), 125) }

        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: postScriptName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
        ])
        var base = UIFont(descriptor: descriptor, size: size)
        if !base.familyName.hasPrefix(familyPrefix) {
            base = fallback(size: size, weight: clampedWeight)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: size * maxScale)
    }

    private var familyPrefix: String {
        self == .display ? "Archivo" : "Atkinson"
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
        guard let designed = system.fontDescriptor.withDesign(fallbackDesign) else { return system }
        return UIFont(descriptor: designed, size: size)
    }
}

enum FontRegistry {
    /// Registers the bundled fonts once, the first time any themed font is built
    /// (app, previews and tests alike).
    static let registered: Bool = {
        registerBundledFonts()
        return true
    }()

    /// Registers every bundled .ttf for this process. Safe to call more than once.
    static func registerBundledFonts(in bundle: Bundle = Bundle(for: BundleToken.self)) {
        let urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is expected on repeat calls; anything else falls back to system fonts.
                error?.release()
            }
        }
    }

    final class BundleToken {}
}
