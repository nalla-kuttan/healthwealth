import SwiftUI
import VolumeCore
import VolumeUI

// MARK: - List view

/// The heatmap as a list, newest first: the equivalent view for VoiceOver and very large text.
struct HeatmapListView: View {
    let grid: HeatmapGrid
    @Binding var selection: HeatmapDay?

    private var months: [(month: Date, days: [HeatmapDay])] {
        let calendar = Calendar.current
        let active = grid.visibleDays.filter { $0.volume != nil }.sorted { $0.date > $1.date }
        let grouped = Dictionary(grouping: active) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
            ForEach(months, id: \.month) { month in
                VStack(alignment: .leading, spacing: 8) {
                    let count = month.days.reduce(0) { $0 + $1.workoutCount }
                    Text("\(month.month.formatted(.dateTime.month(.wide).year())) · \(count) workout\(count == 1 ? "" : "s")")
                        .font(Theme.heading(16))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(month.days) { day in row(day) }
                    }
                    .paperCard(padding: 0)
                }
            }
            if months.isEmpty {
                Text("No workouts in this filter yet.").font(Theme.text(15)).foregroundStyle(Theme.soft)
            }
        }
    }

    private func row(_ day: HeatmapDay) -> some View {
        Button { selection = day } label: {
            HStack(alignment: .center, spacing: 12) {
                HeatmapCell(level: day.level, hasPR: day.hasPR, size: 18, background: Theme.card)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(Theme.text(15, weight: 700))
                        .foregroundStyle(Theme.ink)
                    Text("\(day.workoutCount) workout\(day.workoutCount == 1 ? "" : "s") · \(Format.duration(day.volume?.duration ?? 0)) · \(Self.levelWord(day.level))")
                        .font(Theme.data(12))
                        .foregroundStyle(Theme.soft)
                }
                Spacer(minLength: 8)
                if day.hasPR {
                    HStack(spacing: 6) {
                        MedalMark(size: 16)
                        Text("PR").font(Theme.data(12, weight: 500)).foregroundStyle(Theme.rose)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1).padding(.leading, 14) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows this day's workouts")
    }

    static func levelWord(_ level: Int) -> String {
        switch level {
        case 0: "rest"
        case 1: "light day"
        case 2: "steady day"
        case 3: "hard day"
        default: "peak day"
        }
    }
}

// MARK: - Widget offer

/// Third open: a preview of their own widget and how to add it. iOS has no API to add it for them.
struct WidgetOfferCard: View {
    let snapshot: WidgetSnapshot
    let onDismiss: () -> Void
    @State private var showsSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep your year on your Home Screen").font(Theme.heading()).foregroundStyle(Theme.ink)
            MediumWidgetView(snapshot: snapshot, showsEmptyState: false)
                .padding(14)
                .frame(height: 158)
                .background(Theme.card, in: .rect(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.rule))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the medium widget with your last 16 weeks and streak")
            if showsSteps {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(WidgetSteps.all.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)").font(Theme.title(14)).foregroundStyle(Theme.intaglio)
                            Text(step).font(Theme.text(14)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 16) {
                Button(showsSteps ? "Got it" : "Show me how") {
                    if showsSteps { onDismiss() } else { withAnimation(Motion.crossfade) { showsSteps = true } }
                }
                .font(Theme.text(15, weight: 700))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Theme.ink, in: .capsule)
                Button("Not now", action: onDismiss)
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.intaglio)
            }
        }
        .paperCard()
    }
}

// MARK: - Share card

/// 4:5 card for sharing the year: the denomination numeral, the full grid, a guilloche seal.
/// Rendered off-screen with ImageRenderer at 3× (1080 × 1350 px).
struct YearCard: View {
    let analysis: TrainingAnalysis

    var body: some View {
        let weeks = WidgetSnapshot(analysis: analysis, weekCount: 53).weeks
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("VOLUME").font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.soft)
                Spacer()
                Text(rangeText).font(Theme.data(10)).foregroundStyle(Theme.soft)
            }
            Text(analysis.filter == .all ? "My year of training" : "My year of \(analysis.filter.title.lowercased())")
                .font(Theme.title(24))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(analysis.totals.workouts)").font(Theme.denomination(72)).foregroundStyle(Theme.ink)
                Text("workouts").font(Theme.text(16, weight: 600)).foregroundStyle(Theme.soft)
            }
            HStack(spacing: 22) {
                stat("\(analysis.totals.personalRecords)", "PRs", Theme.rose)
                stat("\(analysis.weeklyStreak)", "wk streak", Theme.ink)
                stat("\(Int((analysis.totals.duration / 3_600).rounded()))", "hours", Theme.ink)
                stat("\(analysis.totals.activeDays)", "active days", Theme.ink)
            }
            CompactHeatmap(weeks: weeks, spacing: 1.6, background: Theme.paper)
                .frame(height: 50)
            HeatmapLegend(background: Theme.paper)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                GuillocheRosette(rings: 30, phase: 1.4).frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every session leaves a mark.").font(Theme.heading(14)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Made with Volume · on-device").font(Theme.data(10)).foregroundStyle(Theme.soft)
                }
            }
        }
        .padding(24)
        .frame(width: 360, height: 450)
        .background(Theme.paper)
    }

    private var rangeText: String {
        let start = analysis.grid.rangeStart.formatted(.dateTime.month(.abbreviated).year())
        let end = analysis.grid.today.formatted(.dateTime.month(.abbreviated).year())
        return "\(start) – \(end)"
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.title(20)).foregroundStyle(color)
            Text(label).font(Theme.text(11)).foregroundStyle(Theme.soft)
        }
    }
}
