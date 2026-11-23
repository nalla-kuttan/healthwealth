import Foundation
import HealthKit
import VolumeCore

/// Read-only HealthKit access: authorization, anchored backfill/incremental sync, and background
/// delivery. Never requests write scopes.
final class HealthSyncService: @unchecked Sendable {
    static let shared = HealthSyncService()

    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.heartRate),
    ]

    /// True until the user has seen the Health permission sheet for these read types.
    func needsAuthorizationPrompt() async -> Bool {
        (try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)) != .unnecessary
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    struct Changes: Sendable {
        var added: [WorkoutRecord]
        var deletedIDs: Set<String>
        var anchor: HKQueryAnchor
    }

    /// With no anchor this is the 365-day historical backfill; with one it returns only workouts
    /// added or deleted since the last sync.
    func fetchChanges(since anchor: HKQueryAnchor?, backfillDays: Int = 365) async throws -> Changes {
        let start = Calendar.current.date(byAdding: .day, value: -backfillDays, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout(predicate)], anchor: anchor)
        let result = try await descriptor.result(for: store)
        return Changes(
            added: result.addedSamples.map(WorkoutMapper.record(from:)),
            deletedIDs: Set(result.deletedObjects.map(\.uuid.uuidString)),
            anchor: result.newAnchor
        )
    }

    #if DEBUG
    /// `-dumpWorkoutMetadata`: writes what each app stored on recent strength workouts (source,
    /// type, metadata keys and values) to Documents/workout-metadata.json, for tuning split
    /// detection against real Hevy/Strong data. Debug builds only; the file never leaves the device
    /// unless copied off over USB.
    func dumpStrengthMetadata() async {
        let start = Calendar.current.date(byAdding: .day, value: -120, to: .now)
        let types: [HKWorkoutActivityType] = [.traditionalStrengthTraining, .functionalStrengthTraining]
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: nil),
            NSCompoundPredicate(orPredicateWithSubpredicates: types.map { HKQuery.predicateForWorkouts(with: $0) }),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                                                 limit: 40)
        guard let workouts = try? await descriptor.result(for: store) else { return }
        let rows: [[String: String]] = workouts.map { w in
            var row = ["source": w.sourceRevision.source.name,
                       "bundle": w.sourceRevision.source.bundleIdentifier,
                       "type": "\(w.workoutActivityType.rawValue)",
                       "start": w.startDate.formatted(.iso8601),
                       "minutes": "\(Int(w.duration / 60))",
                       "activities": "\(w.workoutActivities.count)",
                       "parsedTitle": WorkoutMapper.record(from: w).title ?? "—",
                       "split": WorkoutMapper.record(from: w).strengthSplit.rawValue]
            for (key, value) in w.metadata ?? [:] { row["meta." + key] = "\(value)" }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: docs.appending(path: "workout-metadata.json"))
    }
    #endif

    private var observerQuery: HKObserverQuery?

    /// Registers the long-running observer and immediate background delivery so newly finished
    /// Apple Watch workouts refresh the cache and widgets without opening the app. Must be called
    /// on every launch (including background launches) from `didFinishLaunching`.
    func startObserving(onChange: @escaping @Sendable () async -> Void) {
        guard isAvailable, observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
            let done = CompletionBox(completion)
            guard error == nil else { done.call(); return }
            Task {
                await onChange()
                done.call()
            }
        }
        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { _, _ in }
    }
}

/// HealthKit's observer completion handler isn't annotated `@Sendable`; it is documented as safe
/// to call from any thread, so box it to hand across the Task boundary.
private struct CompletionBox: @unchecked Sendable {
    let handler: HKObserverQueryCompletionHandler
    init(_ handler: @escaping HKObserverQueryCompletionHandler) { self.handler = handler }
    func call() { handler() }
}
