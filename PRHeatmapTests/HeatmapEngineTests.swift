import XCTest
@testable import PRHeatmap

final class HeatmapEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        c.firstWeekday = 1 // Sunday
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func run(_ day: Date, km: Double, minutes: Double, kcal: Double = 500) -> WorkoutRecord {
        WorkoutRecord(start: day, duration: minutes * 60, modality: .running, title: "Run",
                      activeEnergyKcal: kcal, distanceMeters: km * 1000, averageHeartRate: 150)
    }

    // MARK: Grid shape

    func testGridHas53WeeksEndingInCurrentWeek() {
        let builder = HeatmapBuilder(calendar: calendar)
        let today = date(2026, 11, 18) // Wednesday
        let model = builder.build(workouts: [], filter: .all, today: today)

        XCTAssertEqual(model.weeks.count, 53)
        XCTAssertTrue(model.weeks.allSatisfy { $0.days.count == 7 })
        XCTAssertEqual(calendar.component(.weekday, from: model.weeks[0].days[0].date), 1, "weeks start on Sunday")
        let last = model.weeks.last!.days
        XCTAssertTrue(last[3].isToday)
        XCTAssertTrue(last[4].isFuture && last[5].isFuture && last[6].isFuture)
        XCTAssertFalse(last[2].isFuture)
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.days.allSatisfy { $0.level == .rest })
    }

    func testGridRespectsMondayWeekStart() {
        var monday = calendar
        monday.firstWeekday = 2
        let model = HeatmapBuilder(calendar: monday).build(workouts: [], filter: .all, today: date(2026, 11, 18))
        XCTAssertEqual(monday.component(.weekday, from: model.weeks[0].days[0].date), 2)
        XCTAssertEqual(model.weekdaySymbols.first, "M")
        XCTAssertTrue(model.weeks.last!.days[2].isToday)
    }

    // MARK: Volume normalisation

    func testLevelsAreRelativeToUsersOwnBaseline() {
        let normalizer = VolumeNormalizer()
        let today = date(2026, 11, 18)
        var totals: [Date: DayTotal] = [:]
        for i in 0..<20 {
            let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -i * 3, to: today)!)
            totals[day] = DayTotal(kcal: 200, minutes: 30, workoutCount: 1)
        }
        let baseline = normalizer.baseline(for: totals, asOf: today, calendar: calendar)
        XCTAssertEqual(baseline, .init(kcal: 200, minutes: 30))

        XCTAssertEqual(normalizer.level(for: DayTotal(), baseline: baseline), .rest)
        XCTAssertEqual(normalizer.level(for: DayTotal(kcal: 60, minutes: 10, workoutCount: 1), baseline: baseline), .light)
        XCTAssertEqual(normalizer.level(for: DayTotal(kcal: 150, minutes: 22, workoutCount: 1), baseline: baseline), .moderate)
        XCTAssertEqual(normalizer.level(for: DayTotal(kcal: 200, minutes: 30, workoutCount: 1), baseline: baseline), .hard)
        XCTAssertEqual(normalizer.level(for: DayTotal(kcal: 400, minutes: 60, workoutCount: 1), baseline: baseline), .peak)
    }

    func testBeginnerAndEnduranceAthleteBothGetFullRange() {
        let today = date(2026, 11, 18)
        func levels(scale: Double) -> Set<VolumeLevel> {
            let workouts = (0..<60).map { i in
                run(calendar.date(byAdding: .day, value: -i, to: today)!,
                    km: 3 * scale, minutes: (15 + Double(i % 8) * 6) * scale, kcal: (100 + Double(i % 8) * 45) * scale)
            }
            let model = HeatmapBuilder(calendar: calendar).build(workouts: workouts, filter: .all, today: today)
            return Set(model.days.filter { !$0.workouts.isEmpty }.map(\.level))
        }
        XCTAssertEqual(levels(scale: 1), levels(scale: 5), "scale is relative, so 5× the volume looks the same")
        XCTAssertTrue(levels(scale: 1).isSuperset(of: [.light, .moderate, .hard, .peak]))
    }

    func testPercentileNearestRank() {
        XCTAssertEqual(VolumeNormalizer.percentile([1, 2, 3, 4], 0.75), 3)
        XCTAssertEqual(VolumeNormalizer.percentile([5], 0.75), 5)
        XCTAssertEqual(VolumeNormalizer.percentile([], 0.75), 0)
    }

    // MARK: PRs

    func testFirstEffortIsBaselineAndFasterLaterRunIsPR() {
        let first = run(date(2026, 3, 1), km: 5.0, minutes: 27)   // 5:24 /km
        let slower = run(date(2026, 3, 8), km: 5.1, minutes: 29)  // slower pace, but a new longest run
        let faster = run(date(2026, 3, 15), km: 5.0, minutes: 24) // 4:48 /km
        let records = PRDetector().detect([faster, first, slower]) // unsorted input on purpose

        XCTAssertNil(records[first.id], "first effort only sets the baseline")
        XCTAssertEqual(records[slower.id]?.map(\.kind), [.longestDistance(.running)])
        XCTAssertEqual(records[faster.id]?.map(\.kind), [.fastestPace(bucket: "5K")])
        XCTAssertEqual(records[faster.id]?.first?.summary, "Fastest 5K pace · 4:48 /km")
    }

    func testRunCountsTowardLargestBucketWithGPSTolerance() {
        let base = run(date(2026, 3, 1), km: 10.2, minutes: 60)
        let shortTen = run(date(2026, 3, 9), km: 9.85, minutes: 52) // within 2% of 10K
        let records = PRDetector().detect([base, shortTen])
        XCTAssertEqual(records[shortTen.id]?.map(\.kind), [.fastestPace(bucket: "10K")])
    }

    func testEffortPRsNeedFifteenMinutes() {
        func hiit(_ day: Date, minutes: Double, kcal: Double) -> WorkoutRecord {
            WorkoutRecord(start: day, duration: minutes * 60, modality: .other, title: "HIIT",
                          activeEnergyKcal: kcal, averageHeartRate: nil)
        }
        let base = hiit(date(2026, 4, 1), minutes: 20, kcal: 200)   // 10 kcal/min
        let short = hiit(date(2026, 4, 2), minutes: 10, kcal: 150)  // 15 kcal/min but too short
        let better = hiit(date(2026, 4, 3), minutes: 20, kcal: 240) // 12 kcal/min
        let records = PRDetector().detect([base, short, better])
        XCTAssertNil(records[short.id])
        XCTAssertEqual(records[better.id]?.first?.summary, "Effort PR · 12.0 kcal/min")
    }

    func testTrimpUsesHeartRateReserve() {
        let detector = PRDetector()
        let workout = WorkoutRecord(start: .now, duration: 3600, modality: .strength, title: "Lift",
                                    activeEnergyKcal: 300, averageHeartRate: 125) // HRr = 0.5
        XCTAssertEqual(detector.trimp(for: workout)!, 60 * 0.5 * 0.64 * exp(0.96), accuracy: 0.001)
    }

    // MARK: Filter & streak

    func testFilterHidesOtherModalitiesButKeepsTheirPRsSeparate() {
        let today = date(2026, 11, 18)
        let r1 = run(date(2026, 11, 2), km: 5, minutes: 27)
        let r2 = run(date(2026, 11, 9), km: 5, minutes: 25)
        let lift = WorkoutRecord(start: date(2026, 11, 10), duration: 3000, modality: .strength,
                                 title: "Strength · Upper", activeEnergyKcal: 300)
        let builder = HeatmapBuilder(calendar: calendar)

        let all = builder.build(workouts: [r1, r2, lift], filter: .all, today: today)
        let strength = builder.build(workouts: [r1, r2, lift], filter: .only(.strength), today: today)
        XCTAssertEqual(all.workoutCount, 3)
        XCTAssertEqual(all.prCount, 1)
        XCTAssertEqual(strength.workoutCount, 1)
        XCTAssertEqual(strength.prCount, 0)
    }

    func testStreakNeedsTwoWorkoutsAWeekAndIgnoresUnfinishedCurrentWeek() {
        let today = date(2026, 11, 18) // week of Sun 15 Nov has only one workout so far
        let workouts = [
            run(date(2026, 11, 16), km: 5, minutes: 30),
            run(date(2026, 11, 10), km: 5, minutes: 30), run(date(2026, 11, 12), km: 5, minutes: 30),
            run(date(2026, 11, 3), km: 5, minutes: 30), run(date(2026, 11, 5), km: 5, minutes: 30),
            run(date(2026, 10, 27), km: 5, minutes: 30), run(date(2026, 10, 29), km: 5, minutes: 30),
            // week of 18 Oct: only one workout, so the streak stops here
            run(date(2026, 10, 20), km: 5, minutes: 30),
            run(date(2026, 10, 12), km: 5, minutes: 30), run(date(2026, 10, 14), km: 5, minutes: 30),
        ]
        let builder = HeatmapBuilder(calendar: calendar)
        XCTAssertEqual(builder.streakMinimumWorkouts, 2)
        XCTAssertEqual(builder.build(workouts: workouts, filter: .all, today: today).weeklyStreak, 3)

        // A second workout this week extends the streak.
        let extended = workouts + [run(date(2026, 11, 17), km: 5, minutes: 30)]
        XCTAssertEqual(builder.build(workouts: extended, filter: .all, today: today).weeklyStreak, 4)
    }

    func testFutureDaysNeverShowWorkouts() {
        let today = date(2026, 11, 18)
        let tomorrow = run(date(2026, 11, 19), km: 5, minutes: 30)
        let model = HeatmapBuilder(calendar: calendar).build(workouts: [tomorrow], filter: .all, today: today)
        XCTAssertEqual(model.workoutCount, 0)
    }

    // MARK: Performance (PRD 5: 1,000+ workouts in < 300 ms)

    func testBuildsFromSampleYearWellUnderBudget() {
        let today = date(2026, 11, 18)
        let builder = HeatmapBuilder(calendar: calendar)
        var workouts: [WorkoutRecord] = []
        // Six sample years (~200 workouts each) folded into one window gives ~1,200 workouts.
        for seed in 11...16 as ClosedRange<UInt64> {
            workouts += SampleWorkoutSource(seed: seed, calendar: calendar).generate(in: builder.interval(endingAt: today))
        }
        XCTAssertGreaterThan(workouts.count, 1_000)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = builder.build(workouts: workouts, filter: .all, today: today)
        }
        XCTAssertLessThan(elapsed, .milliseconds(300), "took \(elapsed)")
    }
}
