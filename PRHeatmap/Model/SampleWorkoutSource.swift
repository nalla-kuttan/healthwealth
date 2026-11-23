import Foundation

/// Deterministic example workouts for building and tuning the heatmap before HealthKit is wired.
/// Pattern: lift Mon/Thu, run Tue, HIIT or ride Wed, long run or ride Sat, mostly rest Sun,
/// a two-week break in February, and slowly improving fitness so PRs appear through the year.
struct SampleWorkoutSource: WorkoutSource {
    var seed: UInt64 = 11
    var calendar: Calendar = .current

    func workouts(in interval: DateInterval) async throws -> [WorkoutRecord] {
        generate(in: interval)
    }

    func generate(in interval: DateInterval) -> [WorkoutRecord] {
        var rng = SplitMix64(seed: seed)
        var result: [WorkoutRecord] = []
        let firstDay = calendar.startOfDay(for: interval.start)
        let totalDays = max(1, calendar.dateComponents([.day], from: firstDay, to: interval.end).day ?? 1)
        let splits = ["Upper", "Lower", "Push", "Pull", "Full body"]

        for offset in 0...totalDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  day <= interval.end else { break }
            let progress = Double(offset) / Double(totalDays)          // 0 → 1 across the window
            let growth = 0.8 + 0.3 * progress
            let month = calendar.component(.month, from: day)
            let dayOfMonth = calendar.component(.day, from: day)
            if month == 2 && (9...22).contains(dayOfMonth) { continue } // planned break

            let weekday = calendar.component(.weekday, from: day)      // 1 = Sunday
            let plan: [(Double, Modality?)] = switch weekday {
            case 1: [(0.15, .cycling)]
            case 2: [(0.8, .strength)]
            case 3: [(0.65, .running)]
            case 4: [(0.45, .other), (0.3, .cycling)]
            case 5: [(0.75, .strength)]
            case 6: [(0.3, .running)]
            default: [(0.72, nil)] // Saturday long session
            }

            for (index, (probability, planned)) in plan.enumerated() where rng.unit() < probability * growth {
                let isLong = planned == nil
                let modality = planned ?? (rng.unit() < 0.6 ? .running : .cycling)
                let hour = isLong ? 8 : (index == 0 ? 7 : 18)
                let start = calendar.date(bySettingHour: hour, minute: Int(rng.range(0, 50)), second: 0, of: day) ?? day
                // Fitness improves ~8% over the year: faster paces, higher outputs.
                let fitness = 1 + 0.08 * progress + rng.range(-0.03, 0.03)

                switch modality {
                case .strength:
                    let minutes = rng.range(40, 75)
                    result.append(WorkoutRecord(
                        start: start, duration: minutes * 60, modality: .strength,
                        title: "Strength · " + splits[Int(rng.range(0, Double(splits.count))) % splits.count],
                        activeEnergyKcal: minutes * rng.range(5.5, 7.6) * fitness,
                        averageHeartRate: rng.range(112, 132)))
                case .running:
                    let km = isLong ? rng.range(14, 21.4) : (rng.unit() < 0.5 ? rng.range(5, 5.6) : rng.range(6, 10.6))
                    let paceMinPerKm = rng.range(5.2, 6.1) / fitness
                    let minutes = km * paceMinPerKm
                    result.append(WorkoutRecord(
                        start: start, duration: minutes * 60, modality: .running,
                        title: "Outdoor run",
                        activeEnergyKcal: minutes * rng.range(10, 12.5),
                        distanceMeters: km * 1000, averageHeartRate: rng.range(145, 162)))
                case .cycling:
                    let km = isLong ? rng.range(50, 90) : rng.range(20, 45)
                    let minutes = km / (rng.range(24, 29) * fitness) * 60
                    result.append(WorkoutRecord(
                        start: start, duration: minutes * 60, modality: .cycling,
                        title: rng.unit() < 0.4 ? "Indoor cycle" : "Outdoor ride",
                        activeEnergyKcal: minutes * rng.range(8, 10),
                        distanceMeters: km * 1000, averageHeartRate: rng.range(130, 150)))
                case .other:
                    let minutes = rng.range(18, 35)
                    result.append(WorkoutRecord(
                        start: start, duration: minutes * 60, modality: .other,
                        title: "HIIT",
                        activeEnergyKcal: minutes * rng.range(10, 13) * fitness,
                        averageHeartRate: rng.range(150, 168)))
                }
            }
        }
        return result
    }
}

/// Small, fast, deterministic PRNG so previews and tests are stable.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ low: Double, _ high: Double) -> Double { low + unit() * (high - low) }
}

/// Returns no workouts; drives the empty-year state.
struct EmptyWorkoutSource: WorkoutSource {
    func workouts(in interval: DateInterval) async throws -> [WorkoutRecord] { [] }
}
