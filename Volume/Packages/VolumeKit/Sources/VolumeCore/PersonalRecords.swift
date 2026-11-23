import Foundation

/// Standard race-distance bands. A run belongs to the longest band it covers (within 1 %), so a
/// 10.3 km run competes in the 10K band and a 5.0 km run in the 5K band.
public enum DistanceBand: String, Codable, Sendable, CaseIterable {
    case oneK, fiveK, tenK, half, marathon

    public var meters: Double {
        switch self {
        case .oneK: 1_000
        case .fiveK: 5_000
        case .tenK: 10_000
        case .half: 21_097.5
        case .marathon: 42_195
        }
    }

    public var title: String {
        switch self {
        case .oneK: "1K"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "Half Marathon"
        case .marathon: "Marathon"
        }
    }

    public static func band(for distanceMeters: Double) -> DistanceBand? {
        allCases.last { distanceMeters >= $0.meters * 0.99 }
    }
}

public enum PRMetric: Hashable, Codable, Sendable {
    /// Average pace (seconds per km) within a distance band. Lower is better.
    case pace(DistanceBand)
    /// Longest single-session distance (meters).
    case longestDistance
    /// Active kcal per minute for sessions ≥ 15 minutes.
    case calorieRate
    /// Zone-based training impulse for the session.
    case trainingImpulse
    /// Best estimated one-rep max (kg) for a named exercise, from Hevy sets.
    case estimatedMax(String)

    public var lowerIsBetter: Bool {
        if case .pace = self { return true }
        return false
    }

    var key: String {
        switch self {
        case .pace(let band): "pace.\(band.rawValue)"
        case .longestDistance: "distance"
        case .calorieRate: "kcalRate"
        case .trainingImpulse: "trimp"
        case .estimatedMax(let exercise): "e1rm.\(exercise.lowercased())"
        }
    }
}

public struct PersonalRecord: Codable, Sendable, Hashable, Identifiable {
    public var workoutID: String
    public var date: Date
    public var kind: ActivityKind
    public var metric: PRMetric
    public var value: Double
    public var previousBest: Double

    public init(workoutID: String, date: Date, kind: ActivityKind, metric: PRMetric, value: Double, previousBest: Double) {
        self.workoutID = workoutID
        self.date = date
        self.kind = kind
        self.metric = metric
        self.value = value
        self.previousBest = previousBest
    }

    public var id: String { "\(workoutID)|\(kind.rawValue)|\(metric.key)" }

    public var title: String {
        switch metric {
        case .pace(let band): "\(band.title) pace"
        case .longestDistance: "Longest \(kind.displayName.lowercased())"
        // kcal/min from a lift says little about strength, so it's an effort record, not a lift PR.
        case .calorieRate: kind.isStrength ? "Effort PR" : "Peak burn rate"
        case .estimatedMax(let exercise): exercise
        case .trainingImpulse: "Highest training load"
        }
    }

    /// Title qualified by activity where the metric alone is ambiguous ("Peak burn rate · HIIT").
    public var headline: String {
        switch metric {
        case .pace, .longestDistance: title
        case .calorieRate, .trainingImpulse: "\(title) · \(kind.displayName)"
        case .estimatedMax: "\(title) · lift PR"
        }
    }

    public var valueText: String { Self.format(value, metric: metric) }

    public var improvementText: String {
        switch metric {
        case .pace:
            "\(Format.paceDelta(secondsPerKm: previousBest - value)) faster"
        case .longestDistance:
            "+\(Format.distance(value - previousBest))"
        case .calorieRate:
            String(format: "+%.1f kcal/min", value - previousBest)
        case .trainingImpulse:
            "+\(Int((value - previousBest).rounded())) TRIMP"
        case .estimatedMax:
            "+\(Format.weight(value - previousBest)) est. max"
        }
    }

    static func format(_ value: Double, metric: PRMetric) -> String {
        switch metric {
        case .pace: Format.pace(secondsPerKm: value)
        case .longestDistance: Format.distance(value)
        case .calorieRate: String(format: "%.1f kcal/min", value)
        case .trainingImpulse: "\(Int(value.rounded())) TRIMP"
        case .estimatedMax: "\(Format.weight(value)) est. max"
        }
    }
}

/// Chronological single pass that flags a PR whenever a session beats the prior best for the
/// same activity kind and metric. The first qualifying effort only sets the baseline — otherwise
/// a fresh 365-day backfill would light up the first weeks with meaningless "PRs".
public enum PersonalRecordDetector {
    public static let minimumIntensityDuration: TimeInterval = 15 * 60

    public static func detect(in records: [WorkoutRecord], heartRate: HeartRateProfile = HeartRateProfile(),
                              minimumImprovement: Double = 0.001) -> [PersonalRecord] {
        var bests: [String: Double] = [:]
        var found: [PersonalRecord] = []

        for record in records.sorted(by: { $0.start < $1.start }) {
            for segment in record.effectiveSegments {
                for (metric, value) in candidates(for: segment, heartRate: heartRate) {
                    let key = "\(segment.kind.rawValue)|\(metric.key)"
                    guard let best = bests[key] else {
                        bests[key] = value
                        continue
                    }
                    let improved = metric.lowerIsBetter
                        ? value < best * (1 - minimumImprovement)
                        : value > best * (1 + minimumImprovement)
                    if improved {
                        found.append(PersonalRecord(workoutID: record.id, date: record.start, kind: segment.kind,
                                                    metric: metric, value: value, previousBest: best))
                        bests[key] = value
                    }
                }
            }
            // Lift records: best estimated one-rep max per exercise, from working sets.
            for exercise in record.lift?.exercises ?? [] {
                guard let value = exercise.sets.compactMap(\.estimatedOneRepMax).max() else { continue }
                let metric = PRMetric.estimatedMax(exercise.name)
                let key = "lift|\(metric.key)"
                guard let best = bests[key] else { bests[key] = value; continue }
                if value > best + 0.5 {
                    found.append(PersonalRecord(workoutID: record.id, date: record.start, kind: record.kind,
                                                metric: metric, value: value, previousBest: best))
                    bests[key] = value
                }
            }
        }
        return found
    }

    static func candidates(for segment: WorkoutSegment, heartRate: HeartRateProfile) -> [(PRMetric, Double)] {
        var result: [(PRMetric, Double)] = []
        let duration = segment.duration

        if let distance = segment.distanceMeters, distance > 0, duration > 0 {
            if segment.kind == .running, let band = DistanceBand.band(for: distance) {
                let pace = duration / (distance / 1_000)
                if (120...1_200).contains(pace) { result.append((.pace(band), pace)) }
            }
            if segment.kind.tracksDistance, distance >= 500 {
                result.append((.longestDistance, distance))
            }
        }

        if segment.kind.tracksIntensity {
            if duration >= minimumIntensityDuration, let energy = segment.activeEnergyKcal, energy > 0 {
                result.append((.calorieRate, energy / (duration / 60)))
            }
            if let hr = segment.averageHeartRate {
                let trimp = heartRate.trainingImpulse(duration: duration, averageHeartRate: hr)
                if trimp > 0 { result.append((.trainingImpulse, trimp)) }
            }
        }
        return result
    }
}
