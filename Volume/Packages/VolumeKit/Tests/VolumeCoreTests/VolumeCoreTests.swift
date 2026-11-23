import Foundation
import Testing
@testable import VolumeCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 1
    return calendar
}

/// Wednesday 18 Nov 2026, 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_795_003_200)

private func workout(_ kind: ActivityKind, daysAgo: Double, minutes: Double, kcal: Double, km: Double? = nil,
                     hr: Double? = nil, title: String? = nil, id: String = UUID().uuidString) -> WorkoutRecord {
    let start = now.addingTimeInterval(-daysAgo * 86_400 - minutes * 60)
    return WorkoutRecord(id: id, kind: kind, start: start, end: start.addingTimeInterval(minutes * 60),
                         activeEnergyKcal: kcal, distanceMeters: km.map { $0 * 1_000 }, averageHeartRate: hr, title: title)
}

@Suite struct HeatmapTests {
    @Test func gridCoversAYearEndingThisWeek() {
        let grid = HeatmapEngine.build(records: [], personalRecords: [], filter: .all, now: now, calendar: utc)
        #expect((52...53).contains(grid.weeks.count))
        #expect(grid.weeks.allSatisfy { $0.days.count == 7 })
        #expect(grid.visibleDays.count == 365)
        #expect(grid.weeks.last!.days.contains { $0.date == utc.startOfDay(for: now) })
        #expect(grid.visibleDays.allSatisfy { $0.level == 0 })
    }

    @Test func respectsLocaleWeekStart() {
        var monday = utc
        monday.firstWeekday = 2
        let grid = HeatmapEngine.build(records: [], personalRecords: [], filter: .all, now: now, calendar: monday)
        #expect(monday.component(.weekday, from: grid.weeks[0].days[0].date) == 2)
        #expect(grid.weekdayOrder == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func levelsScaleAgainstPersonalBaseline() {
        // Ten ordinary days at 300 kcal / 40 min set the p75; one 2× day must be level 4,
        // one small day level 1, rest days level 0.
        var records = (1...10).map { workout(.running, daysAgo: Double($0), minutes: 40, kcal: 300) }
        records.append(workout(.running, daysAgo: 12, minutes: 80, kcal: 600, id: "big"))
        records.append(workout(.yoga, daysAgo: 13, minutes: 10, kcal: 40, id: "small"))
        let grid = HeatmapEngine.build(records: records, personalRecords: [], filter: .all, now: now, calendar: utc)
        let byID = Dictionary(grid.visibleDays.compactMap { day in day.volume.map { ($0.workoutIDs[0], day.level) } },
                              uniquingKeysWith: { a, _ in a })
        #expect(byID["big"] == 4)
        #expect(byID["small"] == 1)
        #expect(grid.visibleDays.filter { $0.volume == nil }.allSatisfy { $0.level == 0 })
    }

    @Test func filterIsolatesModality() {
        let records = [workout(.running, daysAgo: 1, minutes: 30, kcal: 300),
                       workout(.traditionalStrength, daysAgo: 2, minutes: 60, kcal: 350)]
        let running = HeatmapEngine.build(records: records, personalRecords: [], filter: .running, now: now, calendar: utc)
        #expect(running.visibleDays.filter { $0.volume != nil }.count == 1)
    }

    @Test func multisportSegmentsCountTowardTheirModality() {
        let start = now.addingTimeInterval(-86_400)
        let tri = WorkoutRecord(id: "tri", kind: .multisport, start: start, end: start.addingTimeInterval(5_400),
                                activeEnergyKcal: 900, segments: [
                                    WorkoutSegment(kind: .cycling, start: start, end: start.addingTimeInterval(3_600)),
                                    WorkoutSegment(kind: .running, start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(5_400)),
                                ])
        let volumes = HeatmapEngine.dailyVolumes(records: [tri], filter: .running, calendar: utc)
        #expect(volumes.count == 1)
        #expect(volumes.values.first?.duration == 1_800)
        #expect(abs((volumes.values.first?.energyKcal ?? 0) - 300) < 0.001)
    }

    @Test func percentileInterpolates() {
        #expect(HeatmapEngine.percentile([1, 2, 3, 4, 5], 0.75) == 4)
        #expect(HeatmapEngine.percentile([10, 20], 0.75) == 17.5)
    }

    @Test func weeklyStreakNeedsTwoWorkoutsAndSurvivesAnUnfinishedCurrentWeek() {
        func daysAgo(_ n: Int) -> Date { utc.date(byAdding: .day, value: -n, to: now)! }
        #expect(StreakCalculator.minimumWorkoutsPerWeek == 2)
        // Two workouts in each of the 3 previous weeks, one so far this week.
        let dates = [8, 9, 15, 16, 22, 23].map(daysAgo) + [now]
        #expect(StreakCalculator.weeklyStreak(workoutDates: dates, now: now, calendar: utc) == 3)
        // A second workout this week extends it.
        #expect(StreakCalculator.weeklyStreak(workoutDates: dates + [now], now: now, calendar: utc) == 4)
        // A week with only one workout ends it.
        let gap = [8, 9, 15, 22, 23].map(daysAgo)
        #expect(StreakCalculator.weeklyStreak(workoutDates: gap, now: now, calendar: utc) == 1)
        #expect(StreakCalculator.weeklyStreak(workoutDates: [daysAgo(30), daysAgo(31)], now: now, calendar: utc) == 0)
        // The minimum is configurable.
        #expect(StreakCalculator.weeklyStreak(workoutDates: gap, minimumWorkouts: 1, now: now, calendar: utc) == 3)
    }
}

@Suite struct PersonalRecordTests {
    @Test func firstEffortIsBaselineAndFasterPaceIsPR() {
        let slow = workout(.running, daysAgo: 20, minutes: 30, kcal: 300, km: 5, id: "slow")   // 6:00 /km
        let fast = workout(.running, daysAgo: 10, minutes: 27, kcal: 300, km: 5.05, id: "fast") // 5:21 /km
        let prs = PersonalRecordDetector.detect(in: [fast, slow])
        let pace = prs.filter { if case .pace(.fiveK) = $0.metric { true } else { false } }
        #expect(pace.count == 1)
        #expect(pace.first?.workoutID == "fast")
        #expect(prs.allSatisfy { $0.workoutID != "slow" })
    }

    @Test func distanceBandsUseLongestCoveredDistance() {
        #expect(DistanceBand.band(for: 4_960) == .fiveK)
        #expect(DistanceBand.band(for: 10_300) == .tenK)
        #expect(DistanceBand.band(for: 21_100) == .half)
        #expect(DistanceBand.band(for: 800) == nil)
    }

    @Test func longestRideIsPR() {
        let prs = PersonalRecordDetector.detect(in: [workout(.cycling, daysAgo: 9, minutes: 60, kcal: 500, km: 25),
                                                     workout(.cycling, daysAgo: 2, minutes: 120, kcal: 900, km: 52, id: "long")])
        #expect(prs.contains { $0.workoutID == "long" && $0.metric == .longestDistance })
    }

    @Test func burnRateRequiresFifteenMinutes() {
        let base = workout(.hiit, daysAgo: 9, minutes: 30, kcal: 300)
        let short = workout(.hiit, daysAgo: 5, minutes: 10, kcal: 200, id: "short") // 20 kcal/min but too short
        let long = workout(.hiit, daysAgo: 2, minutes: 20, kcal: 240, id: "long")   // 12 kcal/min
        let prs = PersonalRecordDetector.detect(in: [base, short, long]).filter { $0.metric == .calorieRate }
        #expect(prs.map(\.workoutID) == ["long"])
    }

    @Test func trainingImpulseUsesHeartRateZones() {
        let profile = HeartRateProfile(maximum: 200)
        #expect(profile.zoneWeight(for: 90) == 0)
        #expect(profile.zoneWeight(for: 150) == 3)
        #expect(profile.trainingImpulse(duration: 3_600, averageHeartRate: 170) == 240)
        let prs = PersonalRecordDetector.detect(in: [
            workout(.traditionalStrength, daysAgo: 6, minutes: 45, kcal: 250, hr: 120),
            workout(.traditionalStrength, daysAgo: 1, minutes: 60, kcal: 300, hr: 135, id: "hard"),
        ], heartRate: profile)
        #expect(prs.contains { $0.workoutID == "hard" && $0.metric == .trainingImpulse })
    }
}

@Suite struct RecoveryTests {
    @Test func splitDetectionReadsWorkoutTitles() {
        #expect(StrengthSplit.detect(in: ["Chest Day"]) == .chest)
        #expect(StrengthSplit.detect(in: ["Back"]) == .back)
        #expect(StrengthSplit.detect(in: ["Shoulders & Delts"]) == .shoulders)
        #expect(StrengthSplit.detect(in: ["Arms: Biceps + Triceps"]) == .arms)
        #expect(StrengthSplit.detect(in: ["Hevy", "Leg Day 🔥"]) == .legs)
        #expect(StrengthSplit.detect(in: ["Chest & Triceps"]) == .push)
        #expect(StrengthSplit.detect(in: ["Back and Biceps"]) == .pull)
        #expect(StrengthSplit.detect(in: ["Push Day"]) == .push)
        // Real Hevy names (HKWorkoutBrandName).
        #expect(StrengthSplit.detect(in: ["Super Back"]) == .back)
        #expect(StrengthSplit.detect(in: ["Super chest but didn’t finish 😭"]) == .chest)
        #expect(StrengthSplit.detect(in: ["Armsssss"]) == .arms)
        #expect(StrengthSplit.detect(in: ["LEGGGG DAYYY"]) == .legs)
        #expect(StrengthSplit.detect(in: ["Pulllll"]) == .pull)
        #expect(StrengthSplit.detect(in: [""]) == .unknown)
        #expect(StrengthSplit.detect(in: ["Upper A"]) == .upper)
        #expect(StrengthSplit.detect(in: ["Chest & Back"]) == .upper)
        #expect(StrengthSplit.detect(in: ["Full Body Strength"]) == .fullBody)
        #expect(StrengthSplit.detect(in: [nil]) == .unknown)
    }

    @Test func strainWeightsStayInPRDRanges() {
        for kind in ActivityKind.allCases {
            for split in StrengthSplit.allCases {
                for weight in StrainMap.weights(for: kind, split: split).values {
                    #expect((0.3...1.0).contains(weight))
                }
            }
        }
    }

    @Test func readinessFollowsExponentialDecay() {
        let model = RecoveryModel()
        let event = StrainEvent(workoutID: "a", kind: .running, date: now, strains: [.legs: 0.5])
        let atZero = model.readiness(events: [event], at: now).first { $0.group == .legs }!
        #expect(atZero.readiness == 50)
        #expect(atZero.status == .recovering)

        let tau = MuscleGroup.legs.timeConstant
        let later = model.readiness(events: [event], at: now.addingTimeInterval(tau)).first { $0.group == .legs }!
        #expect(later.readiness == Int((100 * (1 - 0.5 * exp(-1.0))).rounded()))

        let expired = model.readiness(events: [event], at: now.addingTimeInterval(97 * 3_600))
        #expect(expired.allSatisfy { $0.readiness == 100 && $0.status == .primed })
    }

    @Test func statusThresholdsMatchSpec() {
        #expect(ReadinessStatus(readiness: 100) == .primed)
        #expect(ReadinessStatus(readiness: 76) == .primed)
        #expect(ReadinessStatus(readiness: 75) == .recovering)
        #expect(ReadinessStatus(readiness: 45) == .recovering)
        #expect(ReadinessStatus(readiness: 44) == .highStrain)
    }

    @Test func legDayFatiguesLegsNotChest() {
        let legs = workout(.traditionalStrength, daysAgo: 0.1, minutes: 70, kcal: 480, hr: 140, title: "Leg Day")
        let analysis = TrainingAnalysis.compute(records: [legs], now: now, calendar: utc)
        let quads = analysis.recovery.first { $0.group == .legs }!
        let chest = analysis.recovery.first { $0.group == .chest }!
        #expect(quads.readiness < 60)
        #expect(chest.readiness == 100)
    }

    @Test func tagOverridesTitleAndFixesUnnamedLifts() {
        var unnamed = workout(.traditionalStrength, daysAgo: 0.1, minutes: 60, kcal: 380, hr: 130, title: nil)
        #expect(unnamed.needsSplitTag)
        unnamed.splitTag = .arms
        #expect(unnamed.strengthSplit == .arms && !unnamed.needsSplitTag)
        let recovery = TrainingAnalysis.compute(records: [unnamed], now: now, calendar: utc).recovery
        #expect(recovery.min { $0.readiness < $1.readiness }!.group == .arms)

        var named = workout(.traditionalStrength, daysAgo: 1, minutes: 60, kcal: 380, hr: 130, title: "Chest Day")
        named.splitTag = .back
        #expect(named.strengthSplit == .back)
        #expect(!workout(.running, daysAgo: 1, minutes: 30, kcal: 300, hr: 150).needsSplitTag)
    }

    @Test func contributionsAndForecastExplainTheScore() {
        let model = RecoveryModel()
        let events = [
            StrainEvent(workoutID: "legs", kind: .traditionalStrength, date: now.addingTimeInterval(-3_600), strains: [.legs: 0.5]),
            StrainEvent(workoutID: "run", kind: .running, date: now.addingTimeInterval(-30 * 3_600), strains: [.legs: 0.35]),
        ]
        let parts = model.contributions(for: .legs, events: events, at: now)
        #expect(parts.map(\.workoutID) == ["legs", "run"])
        let readiness = model.readiness(events: events, at: now).first { $0.group == .legs }!.readiness
        #expect(abs((100 - parts.reduce(0) { $0 + $1.points }) - readiness) <= 1)

        let forecast = model.forecast(for: .legs, events: events, from: now)
        #expect(readiness < 45)
        let recovering = try! #require(forecast.recoveringAt), primed = try! #require(forecast.primedAt)
        #expect(recovering > now && primed > recovering)
        #expect(forecast.points.first!.readiness == readiness)
        #expect(model.forecast(for: .chest, events: events, from: now).primedAt == nil)
    }

    @Test func strengthBurnRateIsAnEffortPR() {
        let pr = PersonalRecord(workoutID: "a", date: now, kind: .traditionalStrength, metric: .calorieRate,
                                value: 9, previousBest: 8)
        #expect(pr.headline.hasPrefix("Effort PR"))
    }

    @Test func bodyPartDaysLoadTheirOwnGroup() {
        for (title, group) in [("Chest Day", MuscleGroup.chest), ("Back Day", .back), ("Shoulder Day", .shoulders),
                               ("Arm Day", .arms), ("Leg Day", .legs)] {
            let session = workout(.traditionalStrength, daysAgo: 0.1, minutes: 60, kcal: 380, hr: 130, title: title)
            let recovery = TrainingAnalysis.compute(records: [session], now: now, calendar: utc).recovery
            let most = recovery.min { $0.readiness < $1.readiness }!
            #expect(most.group == group, "\(title) should tire \(group) most")
        }
    }
}

@Suite struct AnalysisTests {
    @Test func demoYearProducesPRsStreakAndFatigue() {
        let records = DemoData.records(now: now, calendar: utc)
        let analysis = TrainingAnalysis.compute(records: records, now: now, calendar: utc)
        #expect(analysis.totals.workouts > 150)
        #expect(analysis.totals.personalRecords > 5)
        #expect(analysis.weeklyStreak > 4)
        #expect(analysis.recovery.contains { $0.readiness < 100 })
        #expect(Set(analysis.grid.visibleDays.map(\.level)).isSuperset(of: [0, 1, 2, 3, 4]))
    }

    @Test func aggregatesOver1000WorkoutsWithinBudget() {
        let records = DemoData.records(days: 1_400, now: now, calendar: utc)
        #expect(records.count >= 1_000)
        let analysis = TrainingAnalysis.compute(records: records, now: now, calendar: utc)
        // PRD budget is 300 ms on A14; a debug build on a Mac should land far below it.
        #expect(analysis.computeTime < 0.3)
    }

    @Test func snapshotRoundTripsThroughSharedStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedStore(directory: dir)
        let analysis = TrainingAnalysis.compute(records: DemoData.records(now: now, calendar: utc), now: now, calendar: utc)
        let snapshot = WidgetSnapshot(analysis: analysis, now: now)
        try store.save(snapshot, to: SharedStore.snapshotFile)
        let loaded = try #require(store.load(WidgetSnapshot.self, from: SharedStore.snapshotFile))
        #expect(loaded.weeks.count == WidgetSnapshot.weekCount)
        // Dates lose sub-microsecond precision through JSON, so compare the rendered values.
        #expect(loaded.recovery(at: now).map(\.readiness) == analysis.recovery.map(\.readiness))
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite struct HevyImportTests {
    static let csv = #"""
    "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Bench Press (Barbell)","","",0,"warmup",40,10,,,
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Bench Press (Barbell)","","",1,"normal",80,8,,,8
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Bench Press (Barbell)","","",2,"normal",80,8,,,
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Bench Press (Barbell)","","",3,"failure",82.5,6,,,
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Incline Bench Press (Dumbbell)","","",0,"normal",30,10,,,
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Incline Bench Press (Dumbbell)","","",1,"normal",30,10,,,
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Chest Fly (Cable)","","",0,"normal",15,12,,,
    "Super chest, then arms","16 Nov 2026, 18:11","16 Nov 2026, 19:24","","Bicep Curl (Dumbbell)","","",0,"normal",14,10,,,
    "Super Back","17 Nov 2026, 17:28","17 Nov 2026, 18:33","note with ""quotes""","Lat Pulldown (Cable)","","",0,"normal",60,10,,,
    "Super Back","17 Nov 2026, 17:28","17 Nov 2026, 18:33","","Lat Pulldown (Cable)","","",1,"normal",65,8,,,
    "Super Back","17 Nov 2026, 17:28","17 Nov 2026, 18:33","","Seated Cable Row - V Grip (Cable)","","",0,"normal",55,10,,,
    "Super Back","17 Nov 2026, 17:28","17 Nov 2026, 18:33","","Pull Up","","",0,"normal",,8,,,
    "Old Push","1 Jan 2026, 09:00","1 Jan 2026, 10:00","","Bench Press (Barbell)","","",0,"normal",70,8,,,
    """#

    @Test func parsesSessionsExercisesAndSets() throws {
        let sessions = try HevyCSV.parse(Self.csv)
        #expect(sessions.map(\.title) == ["Old Push", "Super chest, then arms", "Super Back"])
        let chest = sessions[1]
        #expect(chest.detail.exercises.map(\.name) == ["Bench Press (Barbell)", "Incline Bench Press (Dumbbell)",
                                                      "Chest Fly (Cable)", "Bicep Curl (Dumbbell)"])
        #expect(chest.detail.exercises[0].sets.count == 4)
        #expect(chest.detail.exercises[0].workingSets == 3)
        #expect(chest.detail.exercises[0].sets[3].kind == .failure)
        #expect(chest.end.timeIntervalSince(chest.start) == 73 * 60)
        #expect(sessions[2].detail.exercises[2].sets[0].weightKg == nil)
    }

    @Test func poundsAreConverted() throws {
        let quoted = #"""
        "title","start_time","end_time","exercise_title","set_type","weight_lbs","reps"
        "Legs","2 Nov 2026, 07:00","2 Nov 2026, 08:00","Squat (Barbell)","normal",225,5
        """#
        let session = try #require(try HevyCSV.parse(quoted).first)
        #expect(abs((session.detail.exercises[0].sets[0].weightKg ?? 0) - 102.06) < 0.01)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: HevyCSV.ImportError.notHevy) { try HevyCSV.parse("date,weight_kg\n2026-11-01,80") }
    }

    @Test func exercisesMapToMuscleGroups() {
        #expect(ExerciseMuscles.weights(for: "Bench Press (Barbell)")[.chest] == 1)
        #expect(ExerciseMuscles.weights(for: "Lat Pulldown (Cable)")[.back] == 1)
        #expect(ExerciseMuscles.weights(for: "Lateral Raise (Dumbbell)")[.shoulders] == 1)
        #expect(ExerciseMuscles.weights(for: "Hammer Curl (Dumbbell)")[.arms] == 1)
        #expect(ExerciseMuscles.weights(for: "Lying Leg Curl (Machine)")[.legs] == 1)
        #expect(ExerciseMuscles.weights(for: "Triceps Pushdown")[.arms] == 1)
        #expect(ExerciseMuscles.weights(for: "Face Pull")[.shoulders] == 1)
        #expect(ExerciseMuscles.weights(for: "Romanian Deadlift (Barbell)")[.legs] == 1)
        #expect(ExerciseMuscles.weights(for: "Squat (Barbell)")[.legs] == 1)
        #expect(ExerciseMuscles.weights(for: "Crunch").isEmpty)
    }

    @Test func mergeAttachesToHealthWorkoutOrAddsHistory() throws {
        let sessions = try HevyCSV.parse(Self.csv)
        let calendar = Calendar.current
        let healthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 17, minute: 29)))
        let health = WorkoutRecord(id: "hk-back", kind: .traditionalStrength, start: healthStart,
                                   end: healthStart.addingTimeInterval(65 * 60), activeEnergyKcal: 420, title: "Super Back")
        let merged = HevyMerge.merge(health: [health], sessions: sessions)
        #expect(merged.count == 3)
        let back = try #require(merged.first { $0.id == "hk-back" })
        #expect(back.lift?.exercises.count == 3)
        #expect(back.strengthSplit == .back)
        let chest = try #require(merged.first { $0.title == "Super chest, then arms" })
        #expect(chest.sourceName == "Hevy" && chest.activeEnergyKcal == 0)
        // Mostly chest sets with one curl: still a chest day, and chest takes the strain.
        #expect(chest.strengthSplit == .chest)
        let weights = try #require(chest.lift?.muscleWeights)
        #expect(weights[.chest] == 1 && (weights[.arms] ?? 0) < 1)
    }

    @Test func backAndBicepsIsAPullDayNotArms() {
        func ex(_ name: String, _ sets: Int) -> LiftExercise {
            LiftExercise(name: name, sets: Array(repeating: LiftSet(weightKg: 40, reps: 10), count: sets))
        }
        // Real session shape: three back movements, three curl variations, then abs.
        let lift = LiftDetail(exercises: [ex("Lat Pulldown (Cable)", 3), ex("Iso-Lateral Low Row", 3),
                                          ex("Seated Cable Row - V Grip (Cable)", 3), ex("Bicep Curl (Barbell)", 3),
                                          ex("Preacher Curl (Dumbbell)", 3), ex("Hammer Curl (Dumbbell)", 3),
                                          ex("Russian Twist (Weighted)", 3)])
        let record = WorkoutRecord(id: "bb", kind: .traditionalStrength, start: now, end: now.addingTimeInterval(3_600),
                                   activeEnergyKcal: 300, title: "Back & Biceps", lift: lift)
        #expect(record.strengthSplit == .pull)
        #expect(lift.intensity == 18.0 / 16)  // abs sets don't add load
    }

    @Test func estimatedMaxPRsComeFromWorkingSets() throws {
        let merged = HevyMerge.merge(health: [], sessions: try HevyCSV.parse(Self.csv))
        let prs = PersonalRecordDetector.detect(in: merged)
        let bench = try #require(prs.first { $0.metric == .estimatedMax("Bench Press (Barbell)") })
        // Old Push 70×8 → 88.7; new best 80×8 → 101.3 (the failure set 82.5×6 → 99).
        #expect(abs(bench.previousBest - 88.67) < 0.1)
        #expect(abs(bench.value - 101.33) < 0.1)
        #expect(bench.title == "Bench Press (Barbell)")
    }
}
