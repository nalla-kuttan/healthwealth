import Foundation
import Observation

@MainActor
@Observable
final class YearViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var model: HeatmapModel?
    private(set) var filter: ModalityFilter = .all
    private(set) var selectedDate: Date?
    /// Weeks inked in so far during the first-run build animation.
    private(set) var revealedWeeks = Int.max

    private let source: WorkoutSource
    private let builder: HeatmapBuilder
    private let now: () -> Date
    private var workouts: [WorkoutRecord] = []
    private var records: [UUID: [PersonalRecord]] = [:]

    init(source: WorkoutSource, builder: HeatmapBuilder = HeatmapBuilder(), now: @escaping () -> Date = Date.init) {
        self.source = source
        self.builder = builder
        self.now = now
    }

    var selectedDay: DayCell? {
        guard let selectedDate else { return nil }
        return model?.days.first { $0.date == selectedDate }
    }

    func load(animateBuild: Bool) async {
        phase = .loading
        do {
            let today = now()
            workouts = try await source.workouts(in: builder.interval(endingAt: today))
            records = builder.detector.detect(workouts)
            rebuild(selectLatestPR: true)
            phase = .loaded
            if animateBuild { await revealWeeks() }
        } catch {
            phase = .failed("Couldn't read your workouts. \(error.localizedDescription)")
        }
    }

    func setFilter(_ newFilter: ModalityFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        rebuild(selectLatestPR: true)
    }

    func select(_ day: DayCell) {
        guard !day.isFuture else { return }
        selectedDate = day.date
    }

    private func rebuild(selectLatestPR: Bool) {
        let built = builder.build(workouts: workouts, records: records, filter: filter, today: now())
        model = built
        if selectLatestPR || selectedDate == nil {
            selectedDate = (built.latestPRDay ?? built.today)?.date
        }
    }

    /// Columns ink in left to right, about 900 ms in total.
    private func revealWeeks() async {
        guard let count = model?.weeks.count else { return }
        revealedWeeks = 0
        let step = Duration.milliseconds(900 / max(count, 1))
        for week in 1...count {
            try? await Task.sleep(for: step)
            revealedWeeks = week
        }
        revealedWeeks = .max
    }
}
