import SwiftUI
import VolumeCore
import VolumeUI
import WidgetKit

struct VolumeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let recovery: [MuscleReadiness]
    let isSample: Bool
}

struct VolumeProvider: TimelineProvider {
    private let store = SharedStore()

    func placeholder(in context: Context) -> VolumeEntry { sampleEntry() }

    func getSnapshot(in context: Context, completion: @escaping (VolumeEntry) -> Void) {
        if context.isPreview { completion(sampleEntry()); return }
        completion(loadEntries().first ?? sampleEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VolumeEntry>) -> Void) {
        let entries = loadEntries()
        guard let last = entries.last else {
            completion(Timeline(entries: [sampleEntry()], policy: .after(.now.addingTimeInterval(3_600))))
            return
        }
        // The app reloads timelines whenever HealthKit delivers a workout; between those,
        // readiness keeps recovering on its own, hour by hour.
        completion(Timeline(entries: entries, policy: .after(last.date.addingTimeInterval(3_600))))
    }

    /// Hourly entries for the next 6 hours with readiness decayed forward from stored strain events.
    private func loadEntries() -> [VolumeEntry] {
        guard let snapshot = store.load(WidgetSnapshot.self, from: SharedStore.snapshotFile) else { return [] }
        let now = Date.now
        return (0..<6).map { hour in
            let date = now.addingTimeInterval(Double(hour) * 3_600)
            return VolumeEntry(date: date, snapshot: snapshot, recovery: snapshot.recovery(at: date), isSample: false)
        }
    }

    private func sampleEntry() -> VolumeEntry {
        let snapshot = WidgetSnapshot(analysis: TrainingAnalysis.compute(records: DemoData.records()))
        return VolumeEntry(date: .now, snapshot: snapshot, recovery: snapshot.recovery(at: .now), isSample: true)
    }
}

struct VolumeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VolumeEntry

    var body: some View {
        switch family {
        case .systemLarge:
            LargeWidgetView(snapshot: entry.snapshot, recovery: entry.recovery, showsEmptyState: !entry.isSample)
        case .accessoryRectangular:
            AccessoryWidgetView(snapshot: entry.snapshot, recovery: entry.recovery)
        default:
            MediumWidgetView(snapshot: entry.snapshot, showsEmptyState: !entry.isSample)
        }
    }
}

struct VolumeHeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VolumeHeatmap", provider: VolumeProvider()) { entry in
            VolumeWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
        }
        .configurationDisplayName("Training Heatmap")
        .description("Your weekly streak, recent training volume and muscle recovery.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main
struct VolumeWidgetBundle: WidgetBundle {
    var body: some Widget {
        VolumeHeatmapWidget()
    }
}
