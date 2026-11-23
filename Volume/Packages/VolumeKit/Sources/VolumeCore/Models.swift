import Foundation

/// Platform-neutral workout activity kinds. The app maps `HKWorkoutActivityType` onto these,
/// which keeps every engine in this package free of HealthKit and unit-testable on macOS.
public enum ActivityKind: String, Codable, Sendable, CaseIterable {
    case running, walking, hiking, cycling, swimming, rowing, elliptical, stairClimbing
    case traditionalStrength, functionalStrength, coreTraining, hiit, crossTraining
    case yoga, pilates, dance, multisport, other

    public var displayName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Ride"
        case .swimming: "Swim"
        case .rowing: "Row"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stair Climb"
        case .traditionalStrength: "Strength"
        case .functionalStrength: "Functional Strength"
        case .coreTraining: "Core"
        case .hiit: "HIIT"
        case .crossTraining: "Cross Training"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .dance: "Dance"
        case .multisport: "Multisport"
        case .other: "Workout"
        }
    }

    public var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairClimbing: "figure.stair.stepper"
        case .traditionalStrength: "dumbbell.fill"
        case .functionalStrength: "figure.strengthtraining.functional"
        case .coreTraining: "figure.core.training"
        case .hiit: "figure.highintensity.intervaltraining"
        case .crossTraining: "figure.cross.training"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .dance: "figure.dance"
        case .multisport: "medal.fill"
        case .other: "figure.mixed.cardio"
        }
    }

    public var modality: Modality {
        switch self {
        case .traditionalStrength, .functionalStrength, .coreTraining: .strength
        case .running: .running
        case .cycling: .cycling
        default: .hiitOther
        }
    }

    public var isStrength: Bool { modality == .strength }

    /// Kinds where "longest single session distance" is a meaningful PR.
    public var tracksDistance: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .swimming, .rowing: true
        default: false
        }
    }

    /// Kinds evaluated with the Strength/HIIT PR criteria (burn rate, TRIMP).
    public var tracksIntensity: Bool {
        switch self {
        case .traditionalStrength, .functionalStrength, .coreTraining, .hiit, .crossTraining: true
        default: false
        }
    }
}

public enum Modality: String, Codable, Sendable, CaseIterable {
    case strength, running, cycling, hiitOther
}

public enum ModalityFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    case all, strength, running, cycling, hiitOther

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .strength: "Strength"
        case .running: "Running"
        case .cycling: "Cycling"
        case .hiitOther: "HIIT/Other"
        }
    }

    public func includes(_ kind: ActivityKind) -> Bool {
        switch self {
        case .all: true
        case .strength: kind.modality == .strength
        case .running: kind.modality == .running
        case .cycling: kind.modality == .cycling
        case .hiitOther: kind.modality == .hiitOther
        }
    }
}

/// A sub-partition of a workout (an `HKWorkoutActivity` in a multisport session).
public struct WorkoutSegment: Codable, Sendable, Hashable {
    public var kind: ActivityKind
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?

    public init(kind: ActivityKind, start: Date, end: Date, activeEnergyKcal: Double? = nil,
                distanceMeters: Double? = nil, averageHeartRate: Double? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// One workout as ingested from HealthKit (or demo data).
public struct WorkoutRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ActivityKind
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    /// Free text used for split detection: brand name plus any title-like metadata.
    public var title: String?
    public var sourceName: String?
    /// Multisport sub-activities. Empty for single-activity workouts.
    public var segments: [WorkoutSegment]
    /// Day the user tagged in Volume. Wins over the split detected from the title.
    public var splitTag: StrengthSplit?
    /// Exercises, sets and weights from a Hevy export, when this session is in one.
    public var lift: LiftDetail?

    public init(id: String, kind: ActivityKind, start: Date, end: Date, activeEnergyKcal: Double,
                distanceMeters: Double? = nil, averageHeartRate: Double? = nil, maxHeartRate: Double? = nil,
                title: String? = nil, sourceName: String? = nil, segments: [WorkoutSegment] = [],
                lift: LiftDetail? = nil) {
        self.lift = lift
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.title = title
        self.sourceName = sourceName
        self.segments = segments
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public var strengthSplit: StrengthSplit {
        guard kind.isStrength else { return .unknown }
        if let splitTag { return splitTag }
        // Exercises beat the name: the groups that took most of the sets decide the day.
        if let focus = lift?.focus, !focus.isEmpty {
            let parts = Set(focus.filter { $0.value >= 0.6 }.compactMap { StrengthSplit(group: $0.key) })
            return StrengthSplit.combine(parts: parts)
        }
        return StrengthSplit.detect(in: [title])
    }

    /// A strength session Volume can't place on a day: no usable name and no tag.
    public var needsSplitTag: Bool { kind.isStrength && strengthSplit == .unknown }

    /// The units every engine iterates over: multisport sub-activities when present, otherwise the
    /// whole workout as a single segment. Missing segment energy is apportioned by duration and
    /// missing heart rate falls back to the workout average.
    public var effectiveSegments: [WorkoutSegment] {
        guard !segments.isEmpty else {
            return [WorkoutSegment(kind: kind, start: start, end: end, activeEnergyKcal: activeEnergyKcal,
                                   distanceMeters: distanceMeters, averageHeartRate: averageHeartRate)]
        }
        let total = segments.reduce(0) { $0 + $1.duration }
        return segments.map { segment in
            var s = segment
            if s.activeEnergyKcal == nil {
                s.activeEnergyKcal = total > 0 ? activeEnergyKcal * segment.duration / total : 0
            }
            if s.averageHeartRate == nil { s.averageHeartRate = averageHeartRate }
            return s
        }
    }
}

/// Training split for strength sessions, inferred from workout names/brand metadata.
/// Body-part days (chest, back, shoulders, arms, legs) come first; push/pull/upper/full body
/// cover sessions named that way or that mix body parts.
public enum StrengthSplit: String, Codable, Sendable, CaseIterable {
    case chest, back, shoulders, arms, legs, push, pull, upper, fullBody, unknown

    /// The body-part days offered when tagging a workout.
    public static let bodyParts: [StrengthSplit] = [.chest, .back, .shoulders, .arms, .legs]

    public var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .legs: "Legs"
        case .push: "Push"
        case .pull: "Pull"
        case .upper: "Upper Body"
        case .fullBody: "Full Body"
        case .unknown: "Strength"
        }
    }

    private static let partWords: [StrengthSplit: Set<String>] = [
        .chest: ["chest", "bench", "pec", "pecs"],
        .back: ["back", "lats", "lat", "row", "rows", "deadlift", "deadlifts"],
        .shoulders: ["shoulder", "shoulders", "delt", "delts", "ohp"],
        .arms: ["arm", "arms", "bicep", "biceps", "tricep", "triceps", "curls"],
        .legs: ["leg", "legs", "lower", "squat", "squats", "glute", "glutes", "hamstring", "hamstrings",
                "quad", "quads", "calf", "calves"],
    ]

    public static func detect(in texts: [String?]) -> StrengthSplit {
        let text = texts.compactMap { $0 }.joined(separator: " ").lowercased()
        guard !text.isEmpty else { return .unknown }
        if text.contains("full body") || text.contains("full-body") || text.contains("total body")
            || text.contains("whole body") || text.contains("fullbody") {
            return .fullBody
        }
        // Squeeze repeated letters on both sides so stretched names ("Armsssss", "LEGGGG DAY")
        // still match their keyword.
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map { squeeze(String($0)) })
        let parts = Set(partWords.filter { !words.isDisjoint(with: $0.value.map(squeeze)) }.keys)
        let push = words.contains(squeeze("push"))
        let pull = words.contains(squeeze("pull"))
        let upper = words.contains(squeeze("upper"))

        return combine(parts: parts, push: push, pull: pull, upper: upper)
    }

    init?(group: MuscleGroup) {
        switch group {
        case .chest: self = .chest
        case .back: self = .back
        case .shoulders: self = .shoulders
        case .arms: self = .arms
        case .legs: self = .legs
        }
    }

    /// Body parts (plus any push/pull/upper wording) → one split.
    static func combine(parts: Set<StrengthSplit>, push: Bool = false, pull: Bool = false, upper: Bool = false) -> StrengthSplit {
        if parts.contains(.legs) && (parts.count > 1 || push || pull || upper) { return .fullBody }
        if push && pull || upper { return .upper }
        if push { return .push }
        if pull { return .pull }
        if parts.count == 1, let part = parts.first { return part }
        if parts.isEmpty { return .unknown }
        // Two or more upper-body parts: chest/shoulders/arms days are push work, back/arms is pull.
        if parts.isSubset(of: [.chest, .shoulders, .arms]) && !parts.isDisjoint(with: [.chest]) { return .push }
        if parts.isSubset(of: [.back, .arms]) { return .pull }
        return .upper
    }

    /// Collapses runs of the same letter: "armsssss" → "arms", "pull" → "pul".
    static func squeeze(_ word: String) -> String {
        var out = ""
        for c in word where c != out.last { out.append(c) }
        return out
    }
}

/// Heart-rate reference used for zone-based training impulse.
public struct HeartRateProfile: Codable, Sendable, Hashable {
    public var maximum: Double

    public init(maximum: Double = 190) {
        self.maximum = maximum
    }

    /// Uses the highest max heart rate observed in workouts (never below 175 so one easy year
    /// doesn't inflate zones), falling back to 190 bpm.
    public static func estimate(from records: [WorkoutRecord]) -> HeartRateProfile {
        let observed = records.compactMap(\.maxHeartRate).filter { $0 > 100 && $0 < 230 }.max()
        guard let observed else { return HeartRateProfile() }
        return HeartRateProfile(maximum: min(220, max(175, observed)))
    }

    /// Edwards heart-rate zone weight (1–5) for a heart rate; 0 below 50 % of max.
    public func zoneWeight(for heartRate: Double) -> Double {
        let fraction = heartRate / maximum
        switch fraction {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }

    /// Edwards TRIMP approximated from session duration and average-HR zone.
    public func trainingImpulse(duration: TimeInterval, averageHeartRate: Double) -> Double {
        (duration / 60) * zoneWeight(for: averageHeartRate)
    }
}
