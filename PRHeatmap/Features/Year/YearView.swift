import SwiftUI

struct YearView: View {
    @State var viewModel: YearViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                switch viewModel.phase {
                case .loading:
                    loading
                case .failed(let message):
                    Text(message).font(Theme.text()).foregroundStyle(Theme.soft)
                case .loaded:
                    if let model = viewModel.model { content(model) }
                }
            }
            // Bundled fonts are resolved as UIFonts, so rebuild when the text size setting changes.
            .id(dynamicTypeSize)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task { await viewModel.load(animateBuild: !reduceMotion) }
        .sensoryFeedback(.selection, trigger: viewModel.selectedDate)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAST 52 WEEKS")
                .font(Theme.label())
                .tracking(0.8)
                .foregroundStyle(Theme.soft)
            Text("Your year")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Building your year…").font(Theme.text()).foregroundStyle(Theme.soft)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func content(_ model: HeatmapModel) -> some View {
        KPIRow(model: model)
        ModalityFilterBar(selection: viewModel.filter) { viewModel.setFilter($0) }
        HeatmapGridView(
            model: model,
            selectedDate: viewModel.selectedDate,
            revealedWeeks: viewModel.revealedWeeks
        ) { viewModel.select($0) }
        .id(viewModel.filter) // re-anchor on the current week when the filter changes
        LegendView()
        if model.isEmpty {
            EmptyYearCard(filter: viewModel.filter)
        } else if let day = viewModel.selectedDay {
            CellPillView(day: day)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: day.date)
        }
    }
}

private struct KPIRow: View {
    let model: HeatmapModel

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 18) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(model.workoutCount)")
                    .font(Theme.denomination())
                    .monospacedDigit()
                Text("workouts")
                    .font(Theme.text(14, weight: 600))
                    .foregroundStyle(Theme.soft)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            stat("\(model.prCount)", "PRs", color: Theme.rose)
            stat("\(model.weeklyStreak)", "week streak", color: Theme.ink)
        }
        .foregroundStyle(Theme.ink)
    }

    private func stat(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.title(20)).foregroundStyle(color).monospacedDigit()
            Text(label).font(Theme.text(11)).foregroundStyle(Theme.soft)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ModalityFilterBar: View {
    let selection: ModalityFilter
    let onChange: (ModalityFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ModalityFilter.allCases, id: \.self) { filter in
                    let isOn = filter == selection
                    Button(filter.title) { onChange(filter) }
                        .font(Theme.text(13, weight: 700))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isOn ? Theme.paper : Theme.ink)
                        .background(Capsule().fill(isOn ? Theme.ink : Color.clear))
                        .overlay(Capsule().strokeBorder(isOn ? Theme.ink : Theme.rule, lineWidth: 1.5))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityLabel("Filter by modality")
    }
}

private struct LegendView: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Rest")
            HStack(spacing: 3) {
                ForEach(VolumeLevel.allCases, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5).fill(Theme.volume(level)).frame(width: 10, height: 10)
                }
            }
            Text("Peak")
            DayCellView(day: Self.prSample, size: 10)
                .accessibilityHidden(true)
            Text("PR")
        }
        .font(Theme.text(11))
        .foregroundStyle(Theme.soft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lighter cells are rest days, darker cells are harder days. A rose ring marks a personal record.")
    }

    private static let prSample = DayCell(
        date: .distantPast, level: .moderate, isToday: false, isFuture: false, workouts: [],
        records: [PersonalRecord(kind: .effortRate(.other), workoutID: UUID(), date: .distantPast, summary: "")])
}

struct CellPillView: View {
    let day: DayCell

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Format.cellDate(day.date) + (day.isToday ? " · today" : ""))
                .font(Theme.title(15))
                .foregroundStyle(Theme.ink)
            if day.workouts.isEmpty {
                Text("Rest day · no workouts")
                    .font(Theme.data(12))
                    .foregroundStyle(Theme.soft)
            } else {
                Text("\(day.workouts.count) workout\(day.workouts.count == 1 ? "" : "s") · \(Format.duration(minutes: day.totalMinutes)) · \(Format.kcal(day.totalKcal))")
                    .font(Theme.data(12))
                    .foregroundStyle(Theme.soft)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(day.workouts) { workout in
                        Text(detail(for: workout))
                            .font(Theme.text(14))
                            .foregroundStyle(Theme.ink)
                    }
                }
                ForEach(day.records, id: \.self) { record in
                    HStack(spacing: 6) {
                        MedalMark()
                        Text("PR").font(Theme.label()).foregroundStyle(Theme.rose)
                        Text(record.summary).font(Theme.text(14, weight: 700)).foregroundStyle(Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.rule))
        .accessibilityElement(children: .combine)
    }

    private func detail(for workout: WorkoutRecord) -> String {
        if let meters = workout.distanceMeters {
            return "\(workout.title) · \(Format.km(meters)) · \(Format.duration(minutes: workout.minutes))"
        }
        return "\(workout.title) · \(Format.duration(minutes: workout.minutes))"
    }
}

/// The double-ring PR mark.
struct MedalMark: View {
    var size: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.rose, lineWidth: 1.5)
            Circle().strokeBorder(Theme.rose, lineWidth: 1.5).padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct EmptyYearCard: View {
    let filter: ModalityFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(filter == .all ? "Your year starts with one workout" : "No \(filter.title.lowercased()) workouts this year")
                .font(Theme.title(16))
                .foregroundStyle(Theme.ink)
            Text(filter == .all
                 ? "Record a workout on Apple Watch or iPhone and it appears here on its own."
                 : "Try another filter, or record one on Apple Watch or iPhone and it appears here on its own.")
                .font(Theme.text(14))
                .foregroundStyle(Theme.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.rule))
    }
}
