import Foundation

/// Deterministic year of hybrid-athlete training (push/pull/legs + runs + rides, steadily improving
/// pace, a holiday gap and one triathlon). Used for simulator demos (`-demoData`), widget
/// placeholders, previews and performance tests. Never mixed with real HealthKit data.
public enum DemoData {
    public static func records(days: Int = 365, now: Date = .now, calendar: Calendar = .current,
                               seed: UInt64 = 7) -> [WorkoutRecord] {
        var rng = SplitMix64(seed: seed)
        var records: [WorkoutRecord] = []
        let today = calendar.startOfDay(for: now)

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let progress = 1 - Double(offset) / Double(max(days, 1))
            let weekday = calendar.component(.weekday, from: day)
            let weekIndex = offset / 7
            let onHoliday = (150..<164).contains(offset)
            if onHoliday || rng.unit() < 0.14 { continue }

            // Easy pace improves from 5:35 → 4:50 /km over the year.
            let basePace = 335 - 45 * progress + rng.range(-6, 6)
            var dayRecords: [WorkoutRecord] = []
            func add(_ kind: ActivityKind, hour: Int, minutes: Double, kcalPerMinute: Double, distanceKm: Double? = nil,
                     avgHR: Double, title: String? = nil, segments: [WorkoutSegment] = []) {
                guard let start = calendar.date(byAdding: .minute, value: hour * 60 + Int(rng.range(0, 40)), to: day)
                else { return }
                let end = start.addingTimeInterval(minutes * 60)
                guard end <= now else { return }
                dayRecords.append(WorkoutRecord(
                    id: "demo-\(offset)-\(dayRecords.count)", kind: kind, start: start, end: end,
                    activeEnergyKcal: minutes * kcalPerMinute * rng.range(0.9, 1.1),
                    distanceMeters: distanceKm.map { $0 * 1_000 }, averageHeartRate: avgHR,
                    maxHeartRate: min(194, avgHR + rng.range(14, 24)), title: title, sourceName: "Demo",
                    segments: segments.map { segment in
                        var s = segment
                        s.start = start.addingTimeInterval(segment.start.timeIntervalSinceReferenceDate)
                        s.end = start.addingTimeInterval(segment.end.timeIntervalSinceReferenceDate)
                        return s
                    }))
            }
            func run(km: Double, paceOffset: Double, hr: Double, hour: Int = 18) {
                let pace = basePace + paceOffset
                add(.running, hour: hour, minutes: km * pace / 60, kcalPerMinute: 70 * 60 / pace, distanceKm: km, avgHR: hr)
            }

            if offset == 96 {
                // Sprint triathlon: 750 m swim, 20 km ride, 5 km run as HKWorkoutActivity segments.
                let swim = 16.0, bike = 38.0, runMin = 5 * (basePace - 5) / 60
                func seg(_ kind: ActivityKind, _ from: Double, _ to: Double, km: Double) -> WorkoutSegment {
                    WorkoutSegment(kind: kind, start: Date(timeIntervalSinceReferenceDate: from * 60),
                                   end: Date(timeIntervalSinceReferenceDate: to * 60), distanceMeters: km * 1_000)
                }
                add(.multisport, hour: 8, minutes: swim + bike + runMin + 3, kcalPerMinute: 11, avgHR: 162,
                    title: "Sprint Triathlon", segments: [
                        seg(.swimming, 0, swim, km: 0.75),
                        seg(.cycling, swim + 2, swim + 2 + bike, km: 20),
                        seg(.running, swim + 3 + bike, swim + 3 + bike + runMin, km: 5),
                    ])
                records += dayRecords
                continue
            }

            // Body-part split, Monday to Friday, with cardio around it.
            func lift(_ title: String?, kcal: Double = 6.2, hr: ClosedRange<Double> = 116...132) {
                add(.traditionalStrength, hour: 7, minutes: rng.range(50, 65), kcalPerMinute: kcal,
                    avgHR: rng.range(hr.lowerBound, hr.upperBound), title: title)
            }
            switch weekday {
            case 2:
                // This week's chest session was saved without a name, so the demo shows tagging.
                lift(offset < 7 ? nil : "Chest Day")
            case 3:
                lift("Back Day", kcal: 6.4)
                run(km: rng.range(5, 8), paceOffset: 38, hr: rng.range(142, 150))
            case 4:
                lift("Shoulder Day", kcal: 5.8)
            case 5:
                lift("Arm Day", kcal: 5.2, hr: 110...124)
                if weekIndex.isMultiple(of: 2) {
                    add(.hiit, hour: 18, minutes: rng.range(24, 34), kcalPerMinute: rng.range(9.5, 12.5) + 2 * progress, avgHR: rng.range(155, 168))
                } else {
                    run(km: rng.range(5, 6.5), paceOffset: 0, hr: rng.range(160, 168))
                }
            case 6:
                lift("Leg Day", kcal: 7.0, hr: 122...136)
            case 7:
                if weekIndex % 8 == 3 {
                    run(km: 5, paceOffset: -18, hr: rng.range(172, 178), hour: 8)
                } else if weekIndex.isMultiple(of: 2) {
                    run(km: min(22, 10 + 11 * progress + rng.range(-1.5, 1.5)), paceOffset: 26, hr: rng.range(148, 156), hour: 8)
                } else {
                    let km = rng.range(35, 70)
                    add(.cycling, hour: 8, minutes: km / rng.range(26, 30) * 60, kcalPerMinute: 9, distanceKm: km, avgHR: rng.range(136, 148))
                }
            default:
                if rng.unit() < 0.35 {
                    add(.yoga, hour: 9, minutes: 30, kcalPerMinute: 3.4, avgHR: 96)
                }
            }
            records += dayRecords
        }
        return records
    }
}

/// Tiny deterministic PRNG so demo data is identical across launches and tests.
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
    mutating func range(_ lower: Double, _ upper: Double) -> Double { lower + (upper - lower) * unit() }
}
