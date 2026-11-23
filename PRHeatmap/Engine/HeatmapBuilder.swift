import Foundation

struct DayCell: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let level: VolumeLevel
    let isToday: Bool
    let isFuture: Bool
    let workouts: [WorkoutRecord]
    let records: [PersonalRecord]

    var isPR: Bool { !records.isEmpty }
    var totalMinutes: Double { workouts.reduce(0) { $0 + $1.minutes } }
    var totalKcal: Double { workouts.reduce(0) { $0 + $1.activeEnergyKcal } }
}

struct HeatmapWeek: Identifiable, Hashable, Sendable {
    let index: Int
    let days: [DayCell]          // always 7, in locale week order
    let monthLabel: String?      // set on the first week of a month
    var id: Int { index }
}

struct HeatmapModel: Sendable {
    let weeks: [HeatmapWeek]
    let workoutCount: Int
    let prCount: Int
    let weeklyStreak: Int
    let weekdaySymbols: [String] // very short symbols, in locale order

    var isEmpty: Bool { workoutCount == 0 }
    var days: [DayCell] { weeks.flatMap(\.days) }
    var today: DayCell? { days.first(where: \.isToday) }
    var latestPRDay: DayCell? { days.last(where: \.isPR) }
}

/// Turns raw workouts into the 52-week grid. Pure and synchronous so it can be unit-tested
/// and timed against the PRD's 300 ms budget.
struct HeatmapBuilder: Sendable {
    var calendar: Calendar = .current
    var weekCount = 53
    var normalizer = VolumeNormalizer()
    var detector = PRDetector()
    /// A week counts toward the "weekly active streak" when it has at least this many workouts
    /// (in the current filter). Two, so a single walk doesn't hold a streak.
    var streakMinimumWorkouts = 2

    /// Date range to request from HealthKit: start of the first visible week through now.
    func interval(endingAt today: Date) -> DateInterval {
        let start = firstWeekStart(for: today)
        return DateInterval(start: start, end: max(today, start))
    }

    func build(workouts: [WorkoutRecord], filter: ModalityFilter, today: Date) -> HeatmapModel {
        let records = detector.detect(workouts)
        return build(workouts: workouts, records: records, filter: filter, today: today)
    }

    /// Use when PRs are already computed (they don't depend on the filter).
    func build(workouts: [WorkoutRecord], records: [UUID: [PersonalRecord]],
               filter: ModalityFilter, today: Date) -> HeatmapModel {
        let todayStart = calendar.startOfDay(for: today)
        let filtered = workouts.filter { filter.includes($0.modality) }
        let byDay = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.start) }

        var totals: [Date: DayTotal] = [:]
        for (day, list) in byDay {
            totals[day] = DayTotal(kcal: list.reduce(0) { $0 + $1.activeEnergyKcal },
                                   minutes: list.reduce(0) { $0 + $1.minutes },
                                   workoutCount: list.count)
        }
        let baseline = normalizer.baseline(for: totals, asOf: todayStart, calendar: calendar)

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = calendar.locale ?? .current
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")

        var weeks: [HeatmapWeek] = []
        var visibleWorkouts = 0
        var visiblePRs = 0
        var day = firstWeekStart(for: today)
        var previousMonth: Int?

        for weekIndex in 0..<weekCount {
            var cells: [DayCell] = []
            var label: String?
            for _ in 0..<7 {
                let month = calendar.component(.month, from: day)
                if month != previousMonth {
                    // Label the week where a month begins, unless it's too close to the end to fit.
                    if weekIndex < weekCount - 2 { label = monthFormatter.string(from: day) }
                    previousMonth = month
                }
                let isFuture = day > todayStart
                let list = isFuture ? [] : (byDay[day] ?? []).sorted { $0.start < $1.start }
                let dayRecords = list.flatMap { records[$0.id] ?? [] }
                visibleWorkouts += list.count
                visiblePRs += dayRecords.count
                cells.append(DayCell(
                    date: day,
                    level: normalizer.level(for: totals[day] ?? DayTotal(), baseline: baseline),
                    isToday: day == todayStart,
                    isFuture: isFuture,
                    workouts: list,
                    records: dayRecords))
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            weeks.append(HeatmapWeek(index: weekIndex, days: cells, monthLabel: label))
        }

        return HeatmapModel(
            weeks: weeks,
            workoutCount: visibleWorkouts,
            prCount: visiblePRs,
            weeklyStreak: weeklyStreak(weeks),
            weekdaySymbols: orderedWeekdaySymbols())
    }

    /// Consecutive qualifying weeks ending this week. The current week only extends the
    /// streak once it qualifies; an in-progress week never breaks it.
    func weeklyStreak(_ weeks: [HeatmapWeek]) -> Int {
        let qualifies = weeks.map { week in
            week.days.reduce(0) { $0 + $1.workouts.count } >= streakMinimumWorkouts
        }
        guard var index = qualifies.indices.last else { return 0 }
        if !qualifies[index] { index -= 1 }
        var streak = 0
        while index >= 0, qualifies[index] {
            streak += 1
            index -= 1
        }
        return streak
    }

    func firstWeekStart(for today: Date) -> Date {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start
            ?? calendar.startOfDay(for: today)
        return calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: currentWeekStart) ?? currentWeekStart
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
