import Foundation

/// Small, allocation-free formatters (no shared DateFormatter state, safe under Swift 6).
public enum Format {
    public static var usesMiles: Bool { Locale.current.measurementSystem == .us }

    /// "80 kg" or "176 lb", following the region's measurement system.
    public static func weight(_ kilograms: Double, pounds: Bool = Format.usesMiles) -> String {
        let value = pounds ? kilograms / 0.453_592_37 : kilograms
        let rounded = (value * 2).rounded() / 2
        let text = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return "\(text) \(pounds ? "lb" : "kg")"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    public static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted()) kcal"
    }

    public static func distance(_ meters: Double, miles: Bool = Format.usesMiles) -> String {
        if miles { return String(format: "%.2f mi", meters / 1_609.344) }
        return String(format: meters >= 10_000 ? "%.1f km" : "%.2f km", meters / 1_000)
    }

    public static func pace(secondsPerKm: Double, miles: Bool = Format.usesMiles) -> String {
        let perUnit = miles ? secondsPerKm * 1.609344 : secondsPerKm
        let total = Int(perUnit.rounded())
        return String(format: "%d:%02d /%@", total / 60, total % 60, miles ? "mi" : "km")
    }

    public static func paceDelta(secondsPerKm: Double, miles: Bool = Format.usesMiles) -> String {
        pace(secondsPerKm: abs(secondsPerKm), miles: miles)
    }

    public static func hoursAgo(_ date: Date, now: Date = .now) -> String {
        let hours = Int(now.timeIntervalSince(date) / 3_600)
        if hours < 1 { return "just now" }
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
