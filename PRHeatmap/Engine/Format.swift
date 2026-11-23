import Foundation

enum Format {
    /// "1 h 24 m" or "38 m".
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        return hours > 0 ? "\(hours) h \(total % 60) m" : "\(total) m"
    }

    static func kcal(_ value: Double) -> String {
        value.rounded().formatted(.number.grouping(.automatic)) + " kcal"
    }

    static func km(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }

    /// Seconds per km → "4:44 /km".
    static func pace(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    static func cellDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func accessibleDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
