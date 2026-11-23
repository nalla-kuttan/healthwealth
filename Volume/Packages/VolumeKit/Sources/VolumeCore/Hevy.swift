import Foundation

// MARK: - Lift detail

/// One logged set. Weight is always stored in kilograms.
public struct LiftSet: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case normal, warmup, dropset, failure }

    public var kind: Kind
    public var weightKg: Double?
    public var reps: Int?
    public var durationSeconds: Double?
    public var distanceMeters: Double?

    public init(kind: Kind = .normal, weightKg: Double? = nil, reps: Int? = nil,
                durationSeconds: Double? = nil, distanceMeters: Double? = nil) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }

    /// Warm-ups don't count toward fatigue or records.
    public var isWorking: Bool { kind != .warmup && ((reps ?? 0) > 0 || (durationSeconds ?? 0) > 0) }

    /// Epley estimate, trusted only for 1–12 reps.
    public var estimatedOneRepMax: Double? {
        guard isWorking, let w = weightKg, w > 0, let r = reps, (1...12).contains(r) else { return nil }
        return r == 1 ? w : w * (1 + Double(r) / 30)
    }
}

public struct LiftExercise: Codable, Sendable, Hashable {
    public var name: String
    public var sets: [LiftSet]

    public init(name: String, sets: [LiftSet]) {
        self.name = name
        self.sets = sets
    }

    public var workingSets: Int { sets.filter(\.isWorking).count }
    public var muscles: [MuscleGroup: Double] { ExerciseMuscles.weights(for: name) }

    /// "4 × 8 · top 80 kg", or "3 sets" for bodyweight and timed work.
    public var summary: String {
        let working = sets.filter(\.isWorking)
        guard !working.isEmpty else { return "warm-up only" }
        let reps = working.compactMap(\.reps)
        var text = reps.count == working.count && Set(reps).count == 1
            ? "\(working.count) × \(reps[0])"
            : "\(working.count) set\(working.count == 1 ? "" : "s")"
        if let top = working.compactMap(\.weightKg).max(), top > 0 { text += " · top \(Format.weight(top))" }
        return text
    }
}

/// Exercise-level detail for a strength session, from a Hevy export.
public struct LiftDetail: Codable, Sendable, Hashable {
    public var exercises: [LiftExercise]

    public init(exercises: [LiftExercise]) { self.exercises = exercises }

    public var workingSets: Int { exercises.reduce(0) { $0 + $1.workingSets } }

    /// Working sets per muscle group (primary movers count 1, helpers less), scaled so the most
    /// worked group is 1.0. Groups under 15 % of the top one are dropped; the rest sit in 0.3–1.0.
    public var muscleWeights: [MuscleGroup: Double] {
        var load: [MuscleGroup: Double] = [:]
        for exercise in exercises {
            let sets = Double(exercise.workingSets)
            for (group, weight) in exercise.muscles { load[group, default: 0] += sets * weight }
        }
        guard let top = load.values.max(), top > 0 else { return [:] }
        return load.compactMapValues { value in
            let share = value / top
            return share < 0.15 ? nil : max(0.3, share)
        }
    }

    /// Working sets per group counting only each exercise's main mover (no helpers), scaled so
    /// the most trained group is 1.0. Decides the day: back rows don't make it an arm day.
    public var focus: [MuscleGroup: Double] {
        var load: [MuscleGroup: Double] = [:]
        for exercise in exercises {
            for (group, weight) in exercise.muscles where weight >= 1 {
                load[group, default: 0] += Double(exercise.workingSets)
            }
        }
        guard let top = load.values.max(), top > 0 else { return [:] }
        return load.mapValues { $0 / top }
    }

    /// Session load from working sets on tracked muscles (ab work doesn't count): about 16 hard
    /// sets is a solid session (1.0).
    public var intensity: Double {
        let sets = exercises.filter { !$0.muscles.isEmpty }.reduce(0) { $0 + $1.workingSets }
        return min(1.4, max(0.1, Double(sets) / 16))
    }
}

// MARK: - Exercise → muscles

/// Maps Hevy exercise names ("Incline Bench Press (Dumbbell)", "Lat Pulldown (Cable)") to the
/// five recovery groups. First matching rule wins, so specific rules come before general ones.
public enum ExerciseMuscles {
    private static let rules: [(keys: [String], weights: [MuscleGroup: Double])] = [
        (["treadmill", "elliptical", "cycling", "bike", "running", "stair", "jump rope", "ski erg", "rowing machine"],
         [.legs: 0.6]),
        (["rear delt", "face pull", "reverse fly", "reverse pec"], [.shoulders: 1.0, .back: 0.5]),
        (["lateral raise", "front raise", "shoulder press", "overhead press", "military press", "arnold",
          "upright row", "ohp", "landmine press", "push press", "y raise"], [.shoulders: 1.0, .arms: 0.3]),
        (["shrug"], [.back: 0.8, .shoulders: 0.4]),
        (["leg curl", "hamstring curl", "nordic"], [.legs: 1.0]),
        (["curl"], [.arms: 1.0]),
        (["wrist", "forearm", "farmer"], [.arms: 0.6]),
        (["tricep", "skull", "pushdown", "push down", "kickback", "close grip bench", "jm press", "french press"],
         [.arms: 1.0, .chest: 0.3]),
        (["bench", "chest press", "chest fly", "pec deck", "butterfly", "push up", "pushup", "push-up", "dip",
          "crossover", "cable fly", "fly", "floor press", "svend"], [.chest: 1.0, .shoulders: 0.5, .arms: 0.5]),
        (["pulldown", "pull down", "pull up", "pullup", "pull-up", "chin up", "chinup", "chin-up", "row",
          "pullover", "lat ", "lats", "muscle up"], [.back: 1.0, .arms: 0.5]),
        (["romanian", "rdl", "stiff leg", "good morning", "deadlift", "rack pull", "clean", "snatch", "swing"],
         [.legs: 1.0, .back: 0.6]),
        (["back extension", "hyperextension", "superman"], [.back: 0.8, .legs: 0.4]),
        (["squat", "leg press", "lunge", "leg extension", "hip thrust", "glute", "calf", "step up", "step-up",
          "abduct", "adduct", "hack", "sissy", "wall sit", "box jump"], [.legs: 1.0]),
    ]

    public static func weights(for exerciseName: String) -> [MuscleGroup: Double] {
        let name = " " + exerciseName.lowercased() + " "
        return rules.first { rule in rule.keys.contains { name.contains($0) } }?.weights ?? [:]
    }
}

// MARK: - CSV import

/// One Hevy workout from the CSV export (one row per set, grouped back into workouts).
public struct LiftSession: Codable, Sendable, Hashable, Identifiable {
    public var title: String
    public var start: Date
    public var end: Date
    public var detail: LiftDetail

    public var id: String { "hevy-\(Int(start.timeIntervalSince1970))" }
}

public enum HevyCSV {
    public enum ImportError: LocalizedError, Equatable {
        case notHevy
        case noWorkouts

        public var errorDescription: String? {
            switch self {
            case .notHevy: "This doesn't look like a Hevy workout export. In Hevy, choose Export Workouts, not measurements."
            case .noWorkouts: "The file has no workouts in it."
            }
        }
    }

    /// Parses Hevy's "Export Workouts" CSV. Columns are found by header name, so their order
    /// doesn't matter; weights in pounds and distances in miles are converted.
    public static func parse(_ text: String) throws -> [LiftSession] {
        let rows = csvRows(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else {
            throw ImportError.notHevy
        }
        func column(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        guard let titleCol = column("title"), let startCol = column("start_time"),
              let exerciseCol = column("exercise_title") else { throw ImportError.notHevy }
        let endCol = column("end_time")
        let typeCol = column("set_type")
        let repsCol = column("reps")
        let durationCol = column("duration_seconds")
        let kgCol = column("weight_kg"), lbsCol = column("weight_lbs", "weight_lb")
        let kmCol = column("distance_km"), miCol = column("distance_miles", "distance_mi")

        struct Key: Hashable { let title: String; let start: Date }
        var order: [Key] = []
        var ends: [Key: Date] = [:]
        var exercises: [Key: [(name: String, sets: [LiftSet])]] = [:]

        for row in rows.dropFirst() where row.count > max(titleCol, startCol, exerciseCol) {
            guard let start = date(row[startCol]) else { continue }
            let key = Key(title: row[titleCol], start: start)
            if exercises[key] == nil { order.append(key); exercises[key] = [] }
            if let endCol, endCol < row.count, let end = date(row[endCol]) { ends[key] = end }

            func number(_ col: Int?) -> Double? {
                guard let col, col < row.count else { return nil }
                return Double(row[col].trimmingCharacters(in: .whitespaces))
            }
            let weight = number(kgCol) ?? number(lbsCol).map { $0 * 0.453_592_37 }
            let distance = number(kmCol).map { $0 * 1_000 } ?? number(miCol).map { $0 * 1_609.344 }
            let kind: LiftSet.Kind = switch (typeCol.flatMap { $0 < row.count ? row[$0].lowercased() : nil } ?? "") {
            case "warmup", "warm_up", "warm-up": .warmup
            case "dropset", "drop_set": .dropset
            case "failure": .failure
            default: .normal
            }
            let set = LiftSet(kind: kind, weightKg: weight, reps: number(repsCol).map { Int($0) },
                              durationSeconds: number(durationCol), distanceMeters: distance)

            let name = row[exerciseCol].trimmingCharacters(in: .whitespaces)
            if let last = exercises[key]?.indices.last, exercises[key]?[last].name == name {
                exercises[key]?[last].sets.append(set)
            } else {
                exercises[key]?.append((name, [set]))
            }
        }

        let sessions = order.map { key in
            LiftSession(title: key.title, start: key.start, end: ends[key] ?? key.start.addingTimeInterval(3_600),
                        detail: LiftDetail(exercises: (exercises[key] ?? []).map { LiftExercise(name: $0.name, sets: $0.sets) }))
        }
        guard !sessions.isEmpty else { throw ImportError.noWorkouts }
        return sessions.sorted { $0.start < $1.start }
    }

    // "17 Nov 2026, 17:28" (Hevy), with ISO 8601 and a few common variants as fallbacks.
    private static let formatters: [DateFormatter] = ["d MMM yyyy, HH:mm", "d MMM yyyy HH:mm", "yyyy-MM-dd HH:mm:ss",
                                                       "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    static func date(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let iso = try? Date(text, strategy: .iso8601) { return iso }
        return formatters.lazy.compactMap { $0.date(from: text) }.first
    }

    /// RFC 4180: quoted fields, doubled quotes, commas and newlines inside quotes.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(c) }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

// MARK: - Merge with Health

public enum HevyMerge {
    /// Attaches exercise detail to the Health strength workout Hevy wrote for the same session
    /// (starts within 30 minutes). Sessions Health never received become their own workouts, so
    /// history from before Hevy's Health sync still counts.
    public static func merge(health: [WorkoutRecord], sessions: [LiftSession]) -> [WorkoutRecord] {
        guard !sessions.isEmpty else { return health }
        var records = health
        var used = Set<Int>()
        let strength = records.indices.filter { records[$0].kind.isStrength }.sorted { records[$0].start < records[$1].start }

        for session in sessions {
            let match = strength
                .filter { !used.contains($0) && abs(records[$0].start.timeIntervalSince(session.start)) <= 30 * 60 }
                .min { abs(records[$0].start.timeIntervalSince(session.start)) < abs(records[$1].start.timeIntervalSince(session.start)) }
            if let match {
                used.insert(match)
                records[match].lift = session.detail
                if (records[match].title ?? "").isEmpty { records[match].title = session.title }
            } else {
                records.append(WorkoutRecord(id: session.id, kind: .traditionalStrength, start: session.start,
                                             end: max(session.end, session.start.addingTimeInterval(60)),
                                             activeEnergyKcal: 0, title: session.title, sourceName: "Hevy",
                                             lift: session.detail))
            }
        }
        return records.sorted { $0.start < $1.start }
    }
}
