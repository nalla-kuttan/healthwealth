import Foundation

struct PersonalRecord: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Best average pace among runs in a distance bucket (e.g. 5K = runs of 5–10 km).
        case fastestPace(bucket: String)
        case longestDistance(Modality)
        /// Highest kcal per minute, sessions of at least 15 minutes.
        case effortRate(Modality)
        /// Highest Banister training impulse, from duration and heart-rate reserve.
        case trainingImpulse(Modality)
    }

    let kind: Kind
    let workoutID: UUID
    let date: Date
    /// Shown on the cell pill, e.g. "Fastest 5K pace · 4:44 /km".
    let summary: String
}

struct HeartRateProfile: Sendable {
    var resting: Double = 60
    var maximum: Double = 190
}

/// Detects PRs chronologically, so a PR means "best so far at the time".
/// The first qualifying effort in a category only sets the baseline; it is not a PR.
struct PRDetector: Sendable {
    struct Bucket: Sendable {
        let meters: Double
        let label: String
    }

    /// Standard running distances (PRD 4.2). A run counts toward the largest bucket it reaches.
    static let runningBuckets: [Bucket] = [
        Bucket(meters: 1_000, label: "1K"),
        Bucket(meters: 5_000, label: "5K"),
        Bucket(meters: 10_000, label: "10K"),
        Bucket(meters: 21_097.5, label: "half marathon"),
        Bucket(meters: 42_195, label: "marathon"),
    ]

    /// GPS tolerance: a 4.95 km run still counts as a 5K.
    var distanceTolerance = 0.98
    var minimumEffortMinutes = 15.0
    var heartRate = HeartRateProfile()

    func detect(_ workouts: [WorkoutRecord]) -> [UUID: [PersonalRecord]] {
        var best: [PersonalRecord.Kind: Double] = [:]
        var result: [UUID: [PersonalRecord]] = [:]

        func consider(_ kind: PersonalRecord.Kind, value: Double, higherIsBetter: Bool,
                      workout: WorkoutRecord, summary: @autoclosure () -> String) {
            guard value.isFinite, value > 0 else { return }
            if let previous = best[kind] {
                let improved = higherIsBetter ? value > previous : value < previous
                guard improved else { return }
                best[kind] = value
                result[workout.id, default: []].append(
                    PersonalRecord(kind: kind, workoutID: workout.id, date: workout.start, summary: summary()))
            } else {
                best[kind] = value // baseline, not a PR
            }
        }

        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            if workout.modality.isDistanceBased, let meters = workout.distanceMeters, meters > 0 {
                consider(.longestDistance(workout.modality), value: meters, higherIsBetter: true,
                         workout: workout,
                         summary: "Longest \(workout.modality == .running ? "run" : "ride") · \(Format.km(meters))")

                if workout.modality == .running,
                   let bucket = Self.runningBuckets.last(where: { meters >= $0.meters * distanceTolerance }) {
                    let secondsPerKm = workout.duration / (meters / 1000)
                    consider(.fastestPace(bucket: bucket.label), value: secondsPerKm, higherIsBetter: false,
                             workout: workout,
                             summary: "Fastest \(bucket.label) pace · \(Format.pace(secondsPerKm))")
                }
            } else if workout.minutes >= minimumEffortMinutes {
                consider(.effortRate(workout.modality), value: workout.kcalPerMinute, higherIsBetter: true,
                         workout: workout,
                         summary: "Effort PR · \(String(format: "%.1f", workout.kcalPerMinute)) kcal/min")
                if let trimp = trimp(for: workout) {
                    consider(.trainingImpulse(workout.modality), value: trimp, higherIsBetter: true,
                             workout: workout,
                             summary: "Highest TRIMP · \(Int(trimp.rounded()))")
                }
            }
        }
        return result
    }

    /// Banister TRIMP: minutes × HRr × 0.64 × e^(1.92 × HRr).
    func trimp(for workout: WorkoutRecord) -> Double? {
        guard let average = workout.averageHeartRate, heartRate.maximum > heartRate.resting else { return nil }
        let reserve = min(max((average - heartRate.resting) / (heartRate.maximum - heartRate.resting), 0), 1)
        return workout.minutes * reserve * 0.64 * exp(1.92 * reserve)
    }
}
