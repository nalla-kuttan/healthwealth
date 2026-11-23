import Foundation

public struct TrainingTotals: Sendable, Hashable {
    public var workouts: Int
    public var activeDays: Int
    public var duration: TimeInterval
    public var energyKcal: Double
    public var personalRecords: Int
}

/// Everything the dashboard and widgets render, computed in one pass from cached records.
public struct TrainingAnalysis: Sendable {
    public var filter: ModalityFilter
    public var grid: HeatmapGrid
    /// PRs matching the filter, newest first.
    public var personalRecords: [PersonalRecord]
    public var strainEvents: [StrainEvent]
    /// Muscle readiness is global — fatigue doesn't care which filter is selected.
    public var recovery: [MuscleReadiness]
    public var weeklyStreak: Int
    public var totals: TrainingTotals
    public var computeTime: TimeInterval

    public static func compute(records: [WorkoutRecord], filter: ModalityFilter = .all, now: Date = .now,
                               calendar: Calendar = .current, recoveryModel: RecoveryModel = RecoveryModel()) -> TrainingAnalysis {
        let started = Date()
        let heartRate = HeartRateProfile.estimate(from: records)
        let prs = PersonalRecordDetector.detect(in: records, heartRate: heartRate)
            .filter { filter.includes($0.kind) }
        let grid = HeatmapEngine.build(records: records, personalRecords: prs, filter: filter, now: now, calendar: calendar)
        let events = recoveryModel.strainEvents(from: records, heartRate: heartRate, now: now)
        let recovery = recoveryModel.readiness(events: events, at: now)

        let visible = grid.visibleDays
        let active = visible.filter { $0.volume != nil }
        let prsInRange = prs.filter { $0.date >= grid.rangeStart }
        let totals = TrainingTotals(
            workouts: active.reduce(0) { $0 + $1.workoutCount },
            activeDays: active.count,
            duration: active.reduce(0) { $0 + ($1.volume?.duration ?? 0) },
            energyKcal: active.reduce(0) { $0 + ($1.volume?.energyKcal ?? 0) },
            personalRecords: prsInRange.count
        )
        // One date per workout (in the current filter), so the 2-workouts-a-week rule can count them.
        let workoutDates = active.flatMap { Array(repeating: $0.date, count: $0.workoutCount) }
        let streak = StreakCalculator.weeklyStreak(workoutDates: workoutDates, now: now, calendar: calendar)

        return TrainingAnalysis(filter: filter, grid: grid, personalRecords: prs.sorted { $0.date > $1.date },
                                strainEvents: events, recovery: recovery, weeklyStreak: streak, totals: totals,
                                computeTime: Date().timeIntervalSince(started))
    }
}
