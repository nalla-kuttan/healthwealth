import SwiftUI

@main
struct PRHeatmapApp: App {
    var body: some Scene {
        WindowGroup {
            YearView(viewModel: YearViewModel(source: Self.makeSource()))
        }
    }

    /// Sample data until HealthKit ingestion (PRD 4.1) is wired.
    /// Launch with `-EmptyData` to see the empty-year state.
    private static func makeSource() -> WorkoutSource {
        if ProcessInfo.processInfo.arguments.contains("-EmptyData") {
            return EmptyWorkoutSource()
        }
        return SampleWorkoutSource()
    }
}

#Preview("Sample year") {
    YearView(viewModel: YearViewModel(source: SampleWorkoutSource()))
}

#Preview("Empty year") {
    YearView(viewModel: YearViewModel(source: EmptyWorkoutSource()))
}
