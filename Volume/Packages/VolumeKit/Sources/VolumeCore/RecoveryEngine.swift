import Foundation

/// Recovery groups follow a body-part split: chest, back, shoulders, arms, legs.
public enum MuscleGroup: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, legs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .legs: "Legs"
        }
    }

    public var shortName: String { displayName }

    /// Recovery time constant τ (seconds). Big muscle groups clear fatigue slowest; arms fastest.
    public var timeConstant: TimeInterval {
        switch self {
        case .chest: 30 * 3_600
        case .back: 32 * 3_600
        case .shoulders: 28 * 3_600
        case .arms: 24 * 3_600
        case .legs: 36 * 3_600
        }
    }
}

public enum ReadinessStatus: String, Codable, Sendable {
    case primed, recovering, highStrain

    public init(readiness: Int) {
        switch readiness {
        case 76...: self = .primed
        case 45...: self = .recovering
        default: self = .highStrain
        }
    }

    public var title: String {
        switch self {
        case .primed: "Primed"
        case .recovering: "Recovering"
        case .highStrain: "Rest recommended"
        }
    }
}

/// Strain deposited on each muscle group by one workout segment, timestamped at its end.
public struct StrainEvent: Codable, Sendable, Hashable {
    public var workoutID: String
    public var kind: ActivityKind
    public var date: Date
    public var strains: [MuscleGroup: Double]
}

public struct MuscleReadiness: Codable, Sendable, Hashable, Identifiable {
    public var group: MuscleGroup
    public var readiness: Int
    public var residualStrain: Double
    public var lastLoaded: Date?

    public var id: MuscleGroup { group }
    public var status: ReadinessStatus { ReadinessStatus(readiness: readiness) }
}

/// Modality → muscle strain weights. Primary movers sit in 0.8–1.0, secondary in 0.3–0.6.
public enum StrainMap {
    public static func weights(for kind: ActivityKind, split: StrengthSplit = .unknown) -> [MuscleGroup: Double] {
        switch kind {
        case .running: [.legs: 1.0]
        case .walking: [.legs: 0.7]
        case .hiking: [.legs: 1.0, .back: 0.3]
        case .cycling: [.legs: 1.0]
        case .swimming: [.back: 1.0, .shoulders: 0.9, .chest: 0.6, .arms: 0.5, .legs: 0.3]
        case .rowing: [.back: 1.0, .legs: 0.8, .arms: 0.6, .shoulders: 0.3]
        case .elliptical: [.legs: 0.8, .arms: 0.3]
        case .stairClimbing: [.legs: 1.0]
        case .traditionalStrength, .functionalStrength: strengthWeights(split)
        case .coreTraining: [.back: 0.4, .legs: 0.3]
        case .hiit, .crossTraining: [.legs: 0.85, .chest: 0.5, .shoulders: 0.5, .back: 0.4, .arms: 0.4]
        case .yoga, .pilates: [.shoulders: 0.4, .back: 0.3, .legs: 0.3]
        case .dance: [.legs: 0.8]
        case .multisport, .other: [.legs: 0.5, .back: 0.3]
        }
    }

    static func strengthWeights(_ split: StrengthSplit) -> [MuscleGroup: Double] {
        switch split {
        case .chest: [.chest: 1.0, .shoulders: 0.5, .arms: 0.4]
        case .back: [.back: 1.0, .arms: 0.5, .shoulders: 0.3]
        case .shoulders: [.shoulders: 1.0, .arms: 0.4, .chest: 0.3]
        case .arms: [.arms: 1.0, .shoulders: 0.3]
        case .legs: [.legs: 1.0, .back: 0.3]
        case .push: [.chest: 1.0, .shoulders: 0.8, .arms: 0.6]
        case .pull: [.back: 1.0, .arms: 0.7, .shoulders: 0.3]
        case .upper: [.chest: 0.8, .back: 0.8, .shoulders: 0.7, .arms: 0.6]
        case .fullBody, .unknown: [.legs: 0.8, .chest: 0.7, .back: 0.7, .shoulders: 0.5, .arms: 0.5]
        }
    }
}

/// Readiness(t) = 100 × (1 − Σᵢ Sᵢ · e^(−Δtᵢ/τ)) over a trailing 96-hour window.
public struct RecoveryModel: Sendable {
    public var window: TimeInterval = 96 * 3_600
    /// Strain a reference-load session puts on a 1.0-weight muscle group.
    public var peakStrain: Double = 0.6
    public var trimpReference: Double = 120
    public var energyReference: Double = 450
    public var durationReference: TimeInterval = 3_600

    public init() {}

    /// Session load relative to a "solid hour" (≈ 120 TRIMP / 450 kcal / 60 min), clamped so a
    /// single huge session can't zero a muscle on its own.
    public func intensity(of segment: WorkoutSegment, heartRate: HeartRateProfile) -> Double {
        let raw: Double
        if let hr = segment.averageHeartRate, heartRate.trainingImpulse(duration: segment.duration, averageHeartRate: hr) > 0 {
            raw = heartRate.trainingImpulse(duration: segment.duration, averageHeartRate: hr) / trimpReference
        } else if let energy = segment.activeEnergyKcal, energy > 0 {
            raw = energy / energyReference
        } else {
            raw = segment.duration / durationReference
        }
        return min(1.4, max(0.1, raw))
    }

    public func strainEvents(from records: [WorkoutRecord], heartRate: HeartRateProfile, now: Date) -> [StrainEvent] {
        let windowStart = now.addingTimeInterval(-window)
        return records.filter { $0.end > windowStart && $0.start <= now }.flatMap { record in
            record.effectiveSegments.map { segment in
                // With Hevy sets, fatigue follows the muscles actually trained and the set count.
                let lifted = segment.kind.isStrength ? record.lift.flatMap { $0.muscleWeights.isEmpty ? nil : $0 } : nil
                let load = (lifted?.intensity ?? intensity(of: segment, heartRate: heartRate)) * peakStrain
                let weights = lifted?.muscleWeights ?? StrainMap.weights(for: segment.kind, split: record.strengthSplit)
                return StrainEvent(workoutID: record.id, kind: segment.kind, date: min(segment.end, now),
                                   strains: weights.mapValues { $0 * load })
            }
        }
    }

    public func readiness(events: [StrainEvent], at date: Date) -> [MuscleReadiness] {
        MuscleGroup.allCases.map { group in
            var residual = 0.0
            var lastLoaded: Date?
            for event in events {
                let elapsed = date.timeIntervalSince(event.date)
                guard elapsed >= 0, elapsed <= window, let strain = event.strains[group], strain > 0 else { continue }
                residual += strain * exp(-elapsed / group.timeConstant)
                lastLoaded = max(lastLoaded ?? event.date, event.date)
            }
            let readiness = Int((100 * (1 - residual)).rounded())
            return MuscleReadiness(group: group, readiness: min(100, max(0, readiness)),
                                   residualStrain: residual, lastLoaded: lastLoaded)
        }
    }
}

// MARK: - Show the math

/// How much one workout is holding a muscle group down right now, in readiness points.
public struct StrainContribution: Sendable, Hashable, Identifiable {
    public var workoutID: String
    public var kind: ActivityKind
    public var date: Date
    public var points: Int
    public var id: String { workoutID }
}

/// Readiness of one group projected forward, and when it crosses the status thresholds.
public struct RecoveryForecast: Sendable, Hashable {
    public struct Point: Sendable, Hashable {
        public var date: Date
        public var readiness: Int
    }

    public var group: MuscleGroup
    public var points: [Point]
    /// When readiness reaches 45 (leaves "Rest recommended"); nil if it's already there.
    public var recoveringAt: Date?
    /// When readiness reaches 76 (Primed); nil if it's already there.
    public var primedAt: Date?
}

public extension RecoveryModel {
    /// Workouts still weighing on `group` at `date`, biggest first. Points are what each one
    /// takes off the 100 readiness score.
    func contributions(for group: MuscleGroup, events: [StrainEvent], at date: Date) -> [StrainContribution] {
        var byWorkout: [String: StrainContribution] = [:]
        for event in events {
            let elapsed = date.timeIntervalSince(event.date)
            guard elapsed >= 0, elapsed <= window, let strain = event.strains[group], strain > 0 else { continue }
            let points = 100 * strain * exp(-elapsed / group.timeConstant)
            var entry = byWorkout[event.workoutID]
                ?? StrainContribution(workoutID: event.workoutID, kind: event.kind, date: event.date, points: 0)
            entry.points += Int(points.rounded())
            entry.date = max(entry.date, event.date)
            byWorkout[event.workoutID] = entry
        }
        return byWorkout.values.filter { $0.points > 0 }.sorted { $0.points > $1.points }
    }

    /// Hour-by-hour projection over the next `horizon`, assuming no more training.
    func forecast(for group: MuscleGroup, events: [StrainEvent], from date: Date,
                  horizon: TimeInterval = 96 * 3_600, step: TimeInterval = 3_600) -> RecoveryForecast {
        var points: [RecoveryForecast.Point] = []
        var t: TimeInterval = 0
        while t <= horizon {
            let at = date.addingTimeInterval(t)
            let value = readiness(events: events, at: at).first { $0.group == group }?.readiness ?? 100
            points.append(.init(date: at, readiness: value))
            t += step
        }
        func crossing(_ threshold: Int) -> Date? {
            guard let first = points.first, first.readiness < threshold else { return nil }
            return points.first { $0.readiness >= threshold }?.date ?? points.last?.date
        }
        return RecoveryForecast(group: group, points: points, recoveringAt: crossing(45), primedAt: crossing(76))
    }
}
