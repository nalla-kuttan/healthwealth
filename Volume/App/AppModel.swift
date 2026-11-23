import Foundation
import HealthKit
import Observation
import VolumeCore
import WidgetKit

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase: Equatable {
        /// First run: welcome and the read scopes, before the system permission sheet.
        case welcome
        case loading
        /// HealthKit isn't available on this device (e.g. iPad without Health).
        case unavailable
        /// The authorization request itself failed.
        case authorizationFailed(String)
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var analysis: TrainingAnalysis?
    private(set) var isSyncing = false
    /// The 365-day backfill is running (first sync, or after the anchor was lost).
    private(set) var isBackfilling = false
    /// Set when arriving from the welcome flow: the Year tab selects the newest PR once it has built.
    var landOnNewestPR = false
    /// Launch count, for offering the widget on the third open.
    private(set) var openCount = 0
    private let defaults = UserDefaults.standard
    private(set) var lastSyncError: String?
    /// Bumps when a sync brings in workouts that weren't there before (the pulse rule beats once).
    private(set) var newWorkoutBeat = 0
    /// Bumps when a sync finds a personal record that wasn't known before (success haptic).
    private(set) var newPRBeat = 0
    var selectedDay: HeatmapDay?
    var filter: ModalityFilter = .all {
        didSet { if filter != oldValue { selectedDay = nil; recompute() } }
    }

    /// `-demoData` launch argument: deterministic sample year for simulator demos and screenshots.
    let isDemo = ProcessInfo.processInfo.arguments.contains("-demoData")

    /// Workouts from Apple Health (what the on-device cache stores).
    private var records: [WorkoutRecord] = []
    /// Health workouts with Hevy sets attached, plus Hevy-only sessions, with day tags applied.
    private var merged: [WorkoutRecord] = []
    private var recordsByID: [String: WorkoutRecord] = [:]
    /// Sessions from the last Hevy CSV import.
    private(set) var hevySessions: [LiftSession] = []
    private(set) var hevyImportedAt: Date?
    private var hevyLoaded = false
    private static let hevyFile = "hevy-sessions.json"
    private var resyncRequested = false
    private var cacheLoaded = false
    private var knownPRIDs: Set<PersonalRecord.ID>?
    /// Workout ID → day tagged in Volume (for lifts saved without a usable name).
    private(set) var splitTags: [String: StrengthSplit] = [:]
    private var tagsLoaded = false
    private let store = SharedStore()
    private let health = HealthSyncService.shared
    private static let anchorFile = "workouts.anchor"

    private init() {}

    /// Strength sessions in the recovery window that Volume can't place on a day.
    var untaggedRecentLifts: [WorkoutRecord] {
        let start = Date.now.addingTimeInterval(-RecoveryModel().window)
        return merged.filter { $0.end > start && $0.needsSplitTag }.sorted { $0.start > $1.start }
    }

    /// The heatmap cell a workout falls on, for jumping to it from elsewhere.
    func heatmapDay(for workout: WorkoutRecord) -> HeatmapDay? {
        analysis?.grid.weeks.lazy.flatMap(\.days).first { Calendar.current.isDate($0.date, inSameDayAs: workout.start) }
    }

    /// Tags a workout with a body-part day (nil clears it). Re-runs analysis and the widget.
    func tag(_ workoutID: String, as split: StrengthSplit?) {
        splitTags[workoutID] = split
        if !isDemo { try? store.save(splitTags, to: SharedStore.splitTagsFile) }
        setRecords(records)
        publishWidgetSnapshot()
    }

    func workout(id: String) -> WorkoutRecord? { recordsByID[id] }

    /// Removes every day tag set in Volume.
    func clearAllTags() {
        splitTags = [:]
        if !isDemo { store.remove(SharedStore.splitTagsFile) }
        setRecords(records)
        publishWidgetSnapshot()
    }

    var showsWidgetOffer: Bool {
        openCount >= 3 && !defaults.bool(forKey: "widgetOfferDismissed") && (analysis?.totals.workouts ?? 0) > 0
    }

    func dismissWidgetOffer() {
        defaults.set(true, forKey: "widgetOfferDismissed")
        widgetOfferDismissed = true
    }
    private(set) var widgetOfferDismissed = false

    /// Shows the welcome screens again on next launch (Settings › Show the introduction).
    func resetIntroduction() {
        defaults.set(false, forKey: "didFinishWelcome")
        defaults.set(false, forKey: "widgetOfferDismissed")
        widgetOfferDismissed = false
        phase = .welcome
    }

    func workouts(on day: HeatmapDay) -> [WorkoutRecord] {
        (day.volume?.workoutIDs ?? []).compactMap { recordsByID[$0] }.sorted { $0.start < $1.start }
    }

    // MARK: Lifecycle

    func start() async {
        guard phase == .loading else { return }
        let args = ProcessInfo.processInfo.arguments
        if openCount == 0 {
            openCount = defaults.integer(forKey: "openCount") + 1
            defaults.set(openCount, forKey: "openCount")
            widgetOfferDismissed = defaults.bool(forKey: "widgetOfferDismissed")
            if args.contains("-widgetOffer") { openCount = max(openCount, 3); widgetOfferDismissed = false }
        }

        if isDemo {
            // -onboarding: walk through the welcome screens before the demo year loads.
            if args.contains("-onboarding") && !landOnNewestPR {
                phase = .welcome
                return
            }
            setRecords(DemoData.records())
            #if DEBUG
            // -importHevy <path>: import a Hevy CSV on launch (simulator testing).
            if let i = args.firstIndex(of: "-importHevy"), args.indices.contains(i + 1) {
                try? importHevy(from: URL(fileURLWithPath: args[i + 1]))
            }
            #endif
            phase = .ready
            publishWidgetSnapshot()
            #if DEBUG
            // -demoLiveWorkout: simulate a Watch workout with a PR landing in the background.
            if ProcessInfo.processInfo.arguments.contains("-demoLiveWorkout") {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    newWorkoutBeat += 1
                    newPRBeat += 1
                }
            }
            #endif
            return
        }

        // Cold start renders from the on-device cache immediately; HealthKit sync follows.
        loadCacheIfNeeded()
        if !records.isEmpty { phase = .ready }

        guard health.isAvailable else {
            phase = .unavailable
            return
        }

        // Explain the read scopes before iOS shows its permission sheet.
        if records.isEmpty, !defaults.bool(forKey: "didFinishWelcome"), await health.needsAuthorizationPrompt() {
            phase = .welcome
            return
        }
        await connect()
    }

    /// "Connect Apple Health" on the welcome screen.
    func finishWelcome() async {
        defaults.set(true, forKey: "didFinishWelcome")
        landOnNewestPR = true
        phase = .loading
        if isDemo {
            await start()
        } else {
            await connect()
        }
    }

    private func connect() async {
        do {
            try await health.requestAuthorization()
        } catch {
            phase = .authorizationFailed(error.localizedDescription)
            return
        }
        startBackgroundObservation()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dumpWorkoutMetadata") {
            await health.dumpStrengthMetadata()
        }
        #endif
        if analysis == nil { setRecords([]) }
        phase = .ready
        await sync()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dumpHevySummary") { dumpHevySummary() }
        #endif
    }

    func retry() async {
        phase = .loading
        await start()
    }

    /// Called from `didFinishLaunching` so background launches re-register the observer query.
    func startBackgroundObservation() {
        guard !isDemo else { return }
        health.startObserving {
            await AppModel.shared.sync()
        }
    }

    // MARK: Sync

    func sync() async {
        guard !isDemo, health.isAvailable else { return }
        if isSyncing {
            resyncRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        // Background deliveries can arrive before the UI ever loaded the cache; merging into an
        // empty array would otherwise overwrite it with only the newest workouts.
        loadCacheIfNeeded()

        repeat {
            resyncRequested = false
            do {
                let anchor = loadAnchor()
                // A missing anchor means the cache is stale or absent — rebuild from the backfill.
                if anchor == nil { records = [] }
                isBackfilling = anchor == nil
                defer { isBackfilling = false }
                let changes = try await health.fetchChanges(since: anchor)
                var merged = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                let hadRecords = !merged.isEmpty
                let arrivals = changes.added.filter { merged[$0.id] == nil }.count
                for id in changes.deletedIDs { merged[id] = nil }
                for record in changes.added { merged[record.id] = record }
                setRecords(Array(merged.values))
                if hadRecords && arrivals > 0 { newWorkoutBeat += 1 }
                try store.save(records, to: SharedStore.workoutsFile)
                saveAnchor(changes.anchor)
                lastSyncError = nil
                publishWidgetSnapshot()
            } catch {
                lastSyncError = error.localizedDescription
            }
        } while resyncRequested
    }

    // MARK: Analysis

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        if let cached = store.load([WorkoutRecord].self, from: SharedStore.workoutsFile) {
            setRecords(cached)
        }
    }

    private func setRecords(_ newRecords: [WorkoutRecord]) {
        if !tagsLoaded {
            tagsLoaded = true
            if !isDemo { splitTags = store.load([String: StrengthSplit].self, from: SharedStore.splitTagsFile) ?? [:] }
        }
        if !hevyLoaded {
            hevyLoaded = true
            if !isDemo || ProcessInfo.processInfo.arguments.contains("-keepHevy") {
                hevySessions = store.load([LiftSession].self, from: Self.hevyFile) ?? []
                hevyImportedAt = defaults.object(forKey: "hevyImportedAt") as? Date
            }
        }
        records = newRecords.sorted { $0.start < $1.start }
        remerge()
    }

    /// Health + Hevy + tags → the records every engine and view reads.
    private func remerge() {
        merged = HevyMerge.merge(health: records, sessions: hevySessions).map { record in
            var r = record
            r.splitTag = splitTags[record.id]
            return r
        }
        recordsByID = Dictionary(merged.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        recompute()
    }

    private func recompute() {
        analysis = TrainingAnalysis.compute(records: merged, filter: filter)
    }

    // MARK: Hevy import

    /// Imports Hevy's "Export Workouts" CSV, replacing any earlier import. Returns the session count.
    @discardableResult
    func importHevy(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let sessions = try HevyCSV.parse(text)
        hevySessions = sessions
        hevyImportedAt = .now
        if !isDemo || ProcessInfo.processInfo.arguments.contains("-keepHevy") {
            try store.save(sessions, to: Self.hevyFile)
            defaults.set(hevyImportedAt, forKey: "hevyImportedAt")
        }
        remerge()
        publishWidgetSnapshot()
        return sessions.count
    }

    #if DEBUG
    /// `-dumpHevySummary`: writes how the import was read (exercise → muscles, session → day,
    /// matches, lift PRs) to Documents/hevy-summary.json for checking off-device. Debug only.
    func dumpHevySummary() {
        var exercises: [String: (count: Int, muscles: String)] = [:]
        for session in hevySessions {
            for exercise in session.detail.exercises {
                let muscles = exercise.muscles.sorted { $0.value > $1.value }
                    .map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ")
                exercises[exercise.name, default: (0, muscles.isEmpty ? "UNMAPPED" : muscles)].count += 1
            }
        }
        let byStart = Dictionary(merged.map { ($0.start, $0) }, uniquingKeysWith: { a, _ in a })
        let sessions: [[String: String]] = hevySessions.suffix(60).map { session in
            let record = merged.first { $0.lift == session.detail && abs($0.start.timeIntervalSince(session.start)) < 1_800 }
            return ["start": session.start.formatted(.iso8601), "title": session.title,
                    "sets": "\(session.detail.workingSets)",
                    "day": record?.strengthSplit.rawValue ?? "?",
                    "matchedHealth": record.map { $0.id.hasPrefix("hevy-") ? "no" : "yes" } ?? "?"]
        }
        _ = byStart
        let prs = (analysis?.personalRecords ?? []).filter { if case .estimatedMax = $0.metric { true } else { false } }
            .prefix(15).map { "\($0.date.formatted(date: .abbreviated, time: .omitted)) \($0.title): \($0.valueText) (\($0.improvementText))" }
        let summary: [String: Any] = [
            "sessions": hevySessions.count,
            "first": hevySessions.first?.start.formatted(.iso8601) ?? "",
            "last": hevySessions.last?.start.formatted(.iso8601) ?? "",
            "matched": hevyMatchSummary.matched, "added": hevyMatchSummary.added,
            "exercises": exercises.sorted { $0.value.count > $1.value.count }.map { "\($0.value.count)× \($0.key) → \($0.value.muscles)" },
            "recentSessions": sessions,
            "liftPRs": Array(prs),
            "recovery": (analysis?.recovery ?? []).map { "\($0.group.rawValue) \($0.readiness)%" },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted]),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: docs.appending(path: "hevy-summary.json"))
    }
    #endif

    func removeHevyImport() {
        hevySessions = []
        hevyImportedAt = nil
        store.remove(Self.hevyFile)
        defaults.removeObject(forKey: "hevyImportedAt")
        remerge()
        publishWidgetSnapshot()
    }

    /// How many Hevy sessions matched a Health workout vs. added history Health never had.
    var hevyMatchSummary: (matched: Int, added: Int) {
        let added = merged.filter { $0.id.hasPrefix("hevy-") }.count
        return (hevySessions.count - added, added)
    }

    private func publishWidgetSnapshot() {
        let overall = filter == .all ? analysis : TrainingAnalysis.compute(records: merged)
        guard let overall else { return }
        let prIDs = Set(overall.personalRecords.map(\.id))
        if let knownPRIDs, !prIDs.subtracting(knownPRIDs).isEmpty { newPRBeat += 1 }
        knownPRIDs = prIDs
        try? store.save(WidgetSnapshot(analysis: overall), to: SharedStore.snapshotFile)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Anchor persistence

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = store.read(Self.anchorFile) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        try? store.write(data, to: Self.anchorFile)
    }
}
