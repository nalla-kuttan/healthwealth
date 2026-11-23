import Foundation

/// Compact, widget-sized projection of a `TrainingAnalysis`. Strain events travel with it so the
/// widget can decay readiness forward in its own timeline without the app running.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public struct Day: Codable, Sendable, Hashable {
        public var date: Date
        public var level: Int
        public var hasPR: Bool
        public var isVisible: Bool
    }

    public var generatedAt: Date
    /// Oldest week first; each week has 7 days in display order.
    public var weeks: [[Day]]
    public var weeklyStreak: Int
    public var workoutsThisWeek: Int
    public var strainEvents: [StrainEvent]
    public var hasAnyWorkouts: Bool

    public static let weekCount = 20

    public init(analysis: TrainingAnalysis, weekCount: Int = WidgetSnapshot.weekCount, now: Date = .now) {
        generatedAt = now
        weeks = analysis.grid.weeks.suffix(weekCount).map { week in
            week.days.map { Day(date: $0.date, level: $0.level, hasPR: $0.hasPR, isVisible: $0.isVisible) }
        }
        weeklyStreak = analysis.weeklyStreak
        workoutsThisWeek = analysis.grid.weeks.last?.days.reduce(0) { $0 + $1.workoutCount } ?? 0
        strainEvents = analysis.strainEvents
        hasAnyWorkouts = analysis.totals.workouts > 0
    }

    public func recovery(at date: Date, model: RecoveryModel = RecoveryModel()) -> [MuscleReadiness] {
        model.readiness(events: strainEvents, at: date)
    }
}

/// JSON files in the shared App Group container: the workout cache (app only) and the widget
/// snapshot (app writes, widget reads). Nothing here ever leaves the device.
public struct SharedStore: Sendable {
    /// Read from the `AppGroupID` Info.plist key (set from `APP_GROUP_ID` in project.yml).
    public static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "group.com.k8awluhz2a.volume"
    }
    public static let snapshotFile = "widget-snapshot.json"
    public static let workoutsFile = "workouts.json"
    /// Workout ID → day the user tagged in Volume.
    public static let splitTagsFile = "split-tags.json"

    public let directory: URL

    public init(appGroupID: String = SharedStore.appGroupID) {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = group
        } else {
            directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VolumeHeatmap", isDirectory: true)
        }
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    public func write(_ data: Data, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        // Readable after first unlock so background HealthKit delivery can refresh the cache.
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url(for: name), options: .atomic)
        #endif
    }

    public func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    public func save<T: Encodable>(_ value: T, to name: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try write(encoder.encode(value), to: name)
    }

    public func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = read(name) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
