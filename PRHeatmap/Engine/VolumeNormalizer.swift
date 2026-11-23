import Foundation

struct DayTotal: Hashable, Sendable {
    var kcal: Double = 0
    var minutes: Double = 0
    var workoutCount: Int = 0
}

/// Maps a day's workout volume onto the 0–4 ink ramp (PRD 4.2).
///
/// The scale is relative to the user's own trailing 90 days: the 75th percentile of
/// active-day energy and duration is "hard" (level 3). One baseline is used for the whole
/// grid so cells stay comparable across the year.
struct VolumeNormalizer: Sendable {
    struct Baseline: Equatable, Sendable {
        let kcal: Double
        let minutes: Double
    }

    var windowDays = 90
    var percentile = 0.75
    /// Below this many active days in the window, fall back to every active day supplied.
    var minimumSampleDays = 5
    /// Upper bounds of score for light, moderate and hard; anything above is peak.
    var thresholds: (light: Double, moderate: Double, hard: Double) = (0.5, 0.9, 1.25)

    func baseline(for totals: [Date: DayTotal], asOf today: Date, calendar: Calendar) -> Baseline? {
        let active = totals.filter { $0.value.workoutCount > 0 }
        guard !active.isEmpty else { return nil }
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: today)) ?? today
        let recent = active.filter { $0.key >= windowStart && $0.key <= today }.map(\.value)
        let sample = recent.count >= minimumSampleDays ? recent : Array(active.values)
        let kcal = Self.percentile(sample.map(\.kcal), percentile)
        let minutes = Self.percentile(sample.map(\.minutes), percentile)
        return Baseline(kcal: max(kcal, 1), minutes: max(minutes, 1))
    }

    func level(for total: DayTotal, baseline: Baseline?) -> VolumeLevel {
        guard total.workoutCount > 0, let baseline else { return .rest }
        let score = (total.kcal / baseline.kcal + total.minutes / baseline.minutes) / 2
        switch score {
        case ..<thresholds.light: return .light
        case ..<thresholds.moderate: return .moderate
        case ..<thresholds.hard: return .hard
        default: return .peak
        }
    }

    /// Nearest-rank percentile.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
