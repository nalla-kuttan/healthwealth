import Foundation

public struct DailyVolume: Sendable, Hashable {
    public var date: Date
    public var workoutIDs: [String]
    public var duration: TimeInterval
    public var energyKcal: Double
}

/// The user's personal reference for "a big day": the 75th percentile of active-day energy and
/// duration over the trailing 90 days. Normalising against it gives beginners and endurance
/// athletes the same spread of colours.
public struct VolumeBaseline: Codable, Sendable, Hashable {
    public var energyP75: Double
    public var durationP75: TimeInterval
    public var sampleDays: Int

    public static let fallback = VolumeBaseline(energyP75: 350, durationP75: 45 * 60, sampleDays: 0)

    /// 0 = rest, 1–4 = intensity relative to the baseline. A logged workout is never level 0,
    /// even when its source app recorded no energy (duration still counts).
    public func level(energy: Double, duration: TimeInterval) -> Int {
        guard energy > 0 || duration > 0 else { return 0 }
        var ratios: [Double] = []
        if energyP75 > 0, energy > 0 { ratios.append(energy / energyP75) }
        if durationP75 > 0 { ratios.append(duration / durationP75) }
        let score = ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
        switch score {
        case ..<0.5: return 1
        case ..<0.8: return 2
        case ..<1.1: return 3
        default: return 4
        }
    }
}

public struct HeatmapDay: Sendable, Hashable, Identifiable {
    public enum Placement: Sendable, Hashable { case inRange, beforeRange, future }

    public var date: Date
    public var level: Int
    public var volume: DailyVolume?
    public var personalRecords: [PersonalRecord]
    public var placement: Placement

    public var id: Date { date }
    public var hasPR: Bool { !personalRecords.isEmpty }
    public var isVisible: Bool { placement == .inRange }
    public var workoutCount: Int { volume?.workoutIDs.count ?? 0 }
}

public struct HeatmapWeek: Sendable, Hashable, Identifiable {
    public var start: Date
    public var days: [HeatmapDay]
    public var id: Date { start }
}

public struct HeatmapGrid: Sendable, Hashable {
    public var weeks: [HeatmapWeek]
    public var baseline: VolumeBaseline
    public var rangeStart: Date
    public var today: Date
    /// Weekday indexes (1 = Sunday) in display order, honouring the calendar's first weekday.
    public var weekdayOrder: [Int]

    public var visibleDays: [HeatmapDay] { weeks.flatMap(\.days).filter(\.isVisible) }
}

public enum HeatmapEngine {
    public static func dailyVolumes(records: [WorkoutRecord], filter: ModalityFilter,
                                    calendar: Calendar) -> [Date: DailyVolume] {
        var volumes: [Date: DailyVolume] = [:]
        for record in records {
            let segments = record.effectiveSegments.filter { filter.includes($0.kind) }
            guard !segments.isEmpty else { continue }
            let day = calendar.startOfDay(for: record.start)
            var volume = volumes[day] ?? DailyVolume(date: day, workoutIDs: [], duration: 0, energyKcal: 0)
            volume.workoutIDs.append(record.id)
            volume.duration += segments.reduce(0) { $0 + $1.duration }
            volume.energyKcal += segments.reduce(0) { $0 + ($1.activeEnergyKcal ?? 0) }
            volumes[day] = volume
        }
        return volumes
    }

    public static func baseline(from volumes: [Date: DailyVolume], now: Date, calendar: Calendar,
                                windowDays: Int = 90) -> VolumeBaseline {
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)) ?? now
        var sample = volumes.values.filter { $0.date > windowStart && $0.date <= now }
        // Too little recent history (new user, injury break): fall back to everything we have.
        if sample.count < 5 { sample = Array(volumes.values) }
        guard !sample.isEmpty else { return .fallback }

        let energies = sample.map(\.energyKcal).filter { $0 > 0 }
        let durations = sample.map(\.duration).filter { $0 > 0 }
        return VolumeBaseline(
            energyP75: energies.isEmpty ? 0 : percentile(energies, 0.75),
            durationP75: durations.isEmpty ? VolumeBaseline.fallback.durationP75 : percentile(durations, 0.75),
            sampleDays: sample.count
        )
    }

    /// Linear-interpolated percentile (same definition as NumPy's default).
    public static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = p * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    public static func build(records: [WorkoutRecord], personalRecords: [PersonalRecord], filter: ModalityFilter,
                             now: Date, calendar: Calendar, dayCount: Int = 365) -> HeatmapGrid {
        let volumes = dailyVolumes(records: records, filter: filter, calendar: calendar)
        let baseline = baseline(from: volumes, now: now, calendar: calendar)

        var prsByDay: [Date: [PersonalRecord]] = [:]
        for pr in personalRecords where filter.includes(pr.kind) {
            prsByDay[calendar.startOfDay(for: pr.date), default: []].append(pr)
        }

        let today = calendar.startOfDay(for: now)
        let rangeStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: rangeStart)?.start ?? rangeStart
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        var weeks: [HeatmapWeek] = []
        var weekStart = firstWeek
        while weekStart <= lastWeek {
            var days: [HeatmapDay] = []
            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
                let placement: HeatmapDay.Placement =
                    date < rangeStart ? .beforeRange : (date > today ? .future : .inRange)
                let volume = placement == .inRange ? volumes[date] : nil
                let level = volume.map { baseline.level(energy: $0.energyKcal, duration: $0.duration) } ?? 0
                days.append(HeatmapDay(date: date, level: level, volume: volume,
                                       personalRecords: placement == .inRange ? prsByDay[date] ?? [] : [],
                                       placement: placement))
            }
            weeks.append(HeatmapWeek(start: weekStart, days: days))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }

        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return HeatmapGrid(weeks: weeks, baseline: baseline, rangeStart: rangeStart, today: today, weekdayOrder: order)
    }
}

public enum StreakCalculator {
    /// A week keeps the streak alive only with at least this many workouts, so a single walk
    /// doesn't hold a streak.
    public static let minimumWorkoutsPerWeek = 2

    /// Consecutive calendar weeks with at least `minimumWorkouts` workouts. `workoutDates` has one
    /// entry per workout. The current week only extends the streak once it qualifies; until then
    /// the streak counts through last week, so it never "breaks" on a Monday morning.
    public static func weeklyStreak(workoutDates: [Date], minimumWorkouts: Int = minimumWorkoutsPerWeek,
                                    now: Date, calendar: Calendar) -> Int {
        var counts: [Date: Int] = [:]
        for date in workoutDates {
            if let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start { counts[week, default: 0] += 1 }
        }
        let weeks = Set(counts.filter { $0.value >= max(minimumWorkouts, 1) }.keys)
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(cursor) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
