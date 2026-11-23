import Foundation

/// The four filter buckets from PRD 4.4. `other` is shown as "HIIT/Other".
enum Modality: String, CaseIterable, Sendable, Hashable {
    case strength, running, cycling, other

    var title: String {
        switch self {
        case .strength: "Strength"
        case .running: "Running"
        case .cycling: "Cycling"
        case .other: "HIIT/Other"
        }
    }

    /// Cardio PRs are pace/distance based; the rest use effort (kcal/min, TRIMP).
    var isDistanceBased: Bool { self == .running || self == .cycling }
}

/// A filter choice: everything, or one modality.
enum ModalityFilter: Hashable, Sendable, CaseIterable {
    case all
    case only(Modality)

    static var allCases: [ModalityFilter] { [.all] + Modality.allCases.map { .only($0) } }

    var title: String {
        switch self {
        case .all: "All"
        case .only(let m): m.title
        }
    }

    func includes(_ modality: Modality) -> Bool {
        switch self {
        case .all: true
        case .only(let m): m == modality
        }
    }
}

/// Source-agnostic workout, shaped so it can be filled from an `HKWorkout`
/// (or one `HKWorkoutActivity` of a multisport workout) later.
struct WorkoutRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let start: Date
    let duration: TimeInterval
    let modality: Modality
    /// Display name, e.g. "Outdoor run" or "Strength · Upper".
    let title: String
    let activeEnergyKcal: Double
    let distanceMeters: Double?
    let averageHeartRate: Double?

    init(
        id: UUID = UUID(),
        start: Date,
        duration: TimeInterval,
        modality: Modality,
        title: String,
        activeEnergyKcal: Double,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.duration = duration
        self.modality = modality
        self.title = title
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
    }

    var minutes: Double { duration / 60 }
    var kcalPerMinute: Double { minutes > 0 ? activeEnergyKcal / minutes : 0 }
}

/// Heatmap intensity, 0 (rest) … 4 (peak). PRD 4.2.
enum VolumeLevel: Int, Comparable, Sendable, CaseIterable {
    case rest = 0, light, moderate, hard, peak
    static func < (a: VolumeLevel, b: VolumeLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Anything that can hand over a window of workouts: HealthKit later, sample data now.
protocol WorkoutSource: Sendable {
    func workouts(in interval: DateInterval) async throws -> [WorkoutRecord]
}
