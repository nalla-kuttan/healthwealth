import CoreText
import Foundation
// Usage: glyphs <font.ttf> <text> <size> <wght> <wdth> <tracking-em>
let a = CommandLine.arguments
let url = URL(fileURLWithPath: a[1]) as CFURL
let text = a[2]; let size = CGFloat(Double(a[3])!)
let wght = Double(a[4])!, wdth = Double(a[5])!, tracking = CGFloat(Double(a[6])!)
let base = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
let vars: [NSNumber: Double] = [NSNumber(value: 0x77676874): wght, NSNumber(value: 0x77647468): wdth]
let desc = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: vars] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(desc, size, nil)
var chars = Array(text.utf16); var glyphs = [CGGlyph](repeating: 0, count: chars.count)
CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
var adv = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &adv, glyphs.count)
let ascent = CTFontGetAscent(font); let cap = CTFontGetCapHeight(font)
var d = ""; var x: CGFloat = 0
func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
for (i, g) in glyphs.enumerated() {
    if let p = CTFontCreatePathForGlyph(font, g, nil) {
        var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: cap) // baseline at y=cap → top of caps at 0
        if let tp = p.copy(using: &t) {
            tp.applyWithBlock { el in
                let e = el.pointee; let pts = e.points
                switch e.type {
                case .moveToPoint: d += "M\(f(pts[0].x)) \(f(pts[0].y))"
                case .addLineToPoint: d += "L\(f(pts[0].x)) \(f(pts[0].y))"
                case .addQuadCurveToPoint: d += "Q\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y))"
                case .addCurveToPoint: d += "C\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y)) \(f(pts[2].x)) \(f(pts[2].y))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
        }
    }
    x += adv[i].width + (i < glyphs.count - 1 ? tracking * size : 0)
}
_ = ascent
print("{\"width\": \(f(x)), \"capHeight\": \(f(cap)), \"d\": \"\(d)\"}")
