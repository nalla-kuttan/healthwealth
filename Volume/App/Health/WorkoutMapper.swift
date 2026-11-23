import Foundation
import HealthKit
import VolumeCore

/// Converts `HKWorkout` (+ statistics and `HKWorkoutActivity` sub-partitions) into the
/// HealthKit-free `WorkoutRecord` the analytics engines use.
enum WorkoutMapper {
    private static let energyType = HKQuantityType(.activeEnergyBurned)
    private static let heartRateType = HKQuantityType(.heartRate)
    private static let distanceTypes = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]
    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    static func record(from workout: HKWorkout) -> WorkoutRecord {
        let stats = workout.allStatistics
        let kind = kind(for: workout.workoutActivityType)
        let activities = workout.workoutActivities
        let isMultisport = activities.count > 1 || kind == .multisport

        return WorkoutRecord(
            id: workout.uuid.uuidString,
            kind: kind,
            start: workout.startDate,
            end: workout.endDate,
            activeEnergyKcal: stats[energyType]?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
            distanceMeters: distance(in: stats),
            averageHeartRate: stats[heartRateType]?.averageQuantity()?.doubleValue(for: bpm),
            maxHeartRate: stats[heartRateType]?.maximumQuantity()?.doubleValue(for: bpm),
            title: title(for: workout),
            sourceName: workout.sourceRevision.source.name,
            segments: isMultisport ? activities.map { segment(from: $0, workoutEnd: workout.endDate) } : []
        )
    }

    private static func segment(from activity: HKWorkoutActivity, workoutEnd: Date) -> WorkoutSegment {
        let stats = activity.allStatistics
        return WorkoutSegment(
            kind: kind(for: activity.workoutConfiguration.activityType),
            start: activity.startDate,
            end: activity.endDate ?? workoutEnd,
            activeEnergyKcal: stats[energyType]?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            distanceMeters: distance(in: stats),
            averageHeartRate: stats[heartRateType]?.averageQuantity()?.doubleValue(for: bpm)
        )
    }

    private static func distance(in stats: [HKQuantityType: HKStatistics]) -> Double? {
        for type in distanceTypes {
            if let meters = stats[type]?.sumQuantity()?.doubleValue(for: .meter()), meters > 0 { return meters }
        }
        return nil
    }

    /// Brand name plus any title-like string metadata third-party apps (Hevy, Strong, …) attach.
    /// Used to tell chest / back / shoulders / arms / legs (and push, pull, full-body) days apart.
    private static func title(for workout: HKWorkout) -> String? {
        guard let metadata = workout.metadata else { return nil }
        var parts: [String] = []
        // Hevy stores the workout's name here (e.g. "Super Back"); it can be an empty string.
        if let brand = metadata[HKMetadataKeyWorkoutBrandName] as? String { parts.append(brand) }
        for (key, value) in metadata where key != HKMetadataKeyWorkoutBrandName {
            let lower = key.lowercased()
            guard lower.contains("title") || lower.contains("name") || lower.contains("routine")
                || lower.contains("split") else { continue }
            if let text = value as? String { parts.append(text) }
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func kind(for type: HKWorkoutActivityType) -> ActivityKind {
        switch type {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling, .handCycling: .cycling
        case .swimming, .waterFitness: .swimming
        case .rowing, .paddleSports: .rowing
        case .elliptical: .elliptical
        case .stairClimbing, .stairs, .stepTraining: .stairClimbing
        case .traditionalStrengthTraining: .traditionalStrength
        case .functionalStrengthTraining: .functionalStrength
        case .coreTraining: .coreTraining
        case .highIntensityIntervalTraining, .mixedCardio, .jumpRope, .kickboxing, .boxing: .hiit
        case .crossTraining: .crossTraining
        case .yoga, .mindAndBody, .flexibility, .cooldown: .yoga
        case .pilates, .barre: .pilates
        case .socialDance, .cardioDance: .dance
        case .swimBikeRun, .transition: .multisport
        default: .other
        }
    }
}
