import SwiftUI
import VolumeCore
import VolumeUI

/// How the dashboard draws the year: the day grid, or one bar per week.
enum YearStyle: String, CaseIterable, Identifiable {
    case days, weeks
    var id: Self { self }

    var symbol: String { self == .days ? "square.grid.3x3.fill" : "chart.bar.fill" }
    var title: String { self == .days ? "Days" : "Weeks" }
    var caption: String { self == .days ? "Each square is a day" : "Each bar is a week" }
}

/// One week of the heatmap, totalled for the skyline.
struct WeekBar: Identifiable, Hashable {
    let week: HeatmapWeek
    /// Sum of each day's score against the volume baseline (1.0 ≈ one big day).
    let score: Double
    /// 0 = no workouts, 1–4 = this week against a typical training week.
    let level: Int
    let workouts: Int
    let duration: TimeInterval

    var id: Date { week.id }
    var hasPR: Bool { week.days.contains { $0.hasPR && $0.isVisible } }
    var visibleDays: [HeatmapDay] { week.days.filter(\.isVisible) }

    /// The day a tap opens: the newest PR that week, otherwise the biggest day.
    var focusDay: HeatmapDay? {
        let days = visibleDays
        if let pr = days.last(where: \.hasPR) { return pr }
        return days.filter { $0.volume != nil }.max { $0.level < $1.level } ?? days.last
    }

    static func bars(for grid: HeatmapGrid) -> (bars: [WeekBar], typical: Double) {
        let scores = grid.weeks.map { week in
            week.days.filter(\.isVisible).compactMap(\.volume).reduce(0) { $0 + dayScore($1, grid.baseline) }
        }
        let active = scores.filter { $0 > 0 }
        // "Typical" is the 75th-percentile active week, the same cut the day levels use.
        let typical = active.isEmpty ? 1 : HeatmapEngine.percentile(active, 0.75)
        let bars = zip(grid.weeks, scores).map { week, score in
            let volumes = week.days.filter(\.isVisible).compactMap(\.volume)
            let ratio = score / max(typical, 0.001)
            let level: Int = volumes.isEmpty ? 0 : ratio < 0.5 ? 1 : ratio < 0.8 ? 2 : ratio < 1.1 ? 3 : 4
            return WeekBar(week: week, score: score, level: level,
                           workouts: volumes.reduce(0) { $0 + $1.workoutIDs.count },
                           duration: volumes.reduce(0) { $0 + $1.duration })
        }
        return (bars, typical)
    }

    /// The continuous score behind `VolumeBaseline.level`: mean of energy and duration ratios.
    private static func dayScore(_ volume: DailyVolume, _ baseline: VolumeBaseline) -> Double {
        var ratios: [Double] = []
        if baseline.energyP75 > 0, volume.energyKcal > 0 { ratios.append(volume.energyKcal / baseline.energyP75) }
        if baseline.durationP75 > 0 { ratios.append(volume.duration / baseline.durationP75) }
        // A logged workout always shows, even with no energy or duration recorded.
        return ratios.isEmpty ? 0.1 : max(0.1, ratios.reduce(0, +) / Double(ratios.count))
    }
}

/// The year as 52–53 weekly columns that fit the width without scrolling. Tapping a week opens its
/// PR or biggest day and shows that week's seven days underneath; touch-and-hold slides across weeks.
struct WeeklySkylineView: View {
    let grid: HeatmapGrid
    @Binding var selection: HeatmapDay?
    var pending: HeatmapView.Pending = .none
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBuilt = false

    private let chartHeight: CGFloat = 132
    private let medalRoom: CGFloat = 10
    private let spacing: CGFloat = 2

    private var data: (bars: [WeekBar], typical: Double) { WeekBar.bars(for: grid) }

    var body: some View {
        let data = data
        let peak = max(data.bars.map(\.score).max() ?? 0, data.typical * 1.15, 0.001)
        let selectedWeek = data.bars.first { bar in bar.week.days.contains { $0.id == selection?.id } }

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let pitch = proxy.size.width / CGFloat(max(data.bars.count, 1))
                ZStack(alignment: .bottomLeading) {
                    typicalLine(y: chartHeight - chartHeight * data.typical / peak, width: proxy.size.width)
                    bars(data.bars, peak: peak, pitch: pitch, selectedWeek: selectedWeek)
                    Rectangle().fill(Theme.rule).frame(height: 1)
                }
                .frame(height: chartHeight + medalRoom, alignment: .bottom)
                .contentShape(.rect)
                .onTapGesture(coordinateSpace: .local) { location in
                    guard let bar = bar(at: location.x, pitch: pitch, in: data.bars) else { return }
                    selection = selectedWeek?.id == bar.id ? nil : bar.focusDay
                }
                .gesture(scrub(pitch: pitch, bars: data.bars, selectedWeek: selectedWeek))
                .overlay(alignment: .topLeading) {
                    monthLabels(data.bars, pitch: pitch).offset(y: chartHeight + medalRoom + 4)
                }
            }
            .frame(height: chartHeight + medalRoom + 18)

            if let selectedWeek { WeekStrip(bar: selectedWeek, selection: $selection) }
        }
        .animation(reduceMotion ? nil : Motion.crossfade, value: selectedWeek?.id)
        .sensoryFeedback(.selection, trigger: selectedWeek?.id)
        .task {
            guard !isBuilt else { return }
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(150)) }
            isBuilt = true
        }
    }

    private func bars(_ bars: [WeekBar], peak: Double, pitch: CGFloat, selectedWeek: WeekBar?) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                let height = isBuilt ? max(bar.level == 0 ? 2 : 4, chartHeight * bar.score / peak) : 2
                let isSelected = selectedWeek?.id == bar.id
                let isCurrent = bar.week.days.contains { $0.date == grid.today }
                VStack(spacing: 3) {
                    if bar.hasPR && isBuilt {
                        Circle().fill(Theme.rose).frame(width: 5, height: 5).transition(.stamp)
                    }
                    UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
                        .fill(Theme.volume(level: bar.level))
                        .frame(height: height)
                        .overlay {
                            if isCurrent && isBuilt {
                                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
                                    .stroke(Theme.soft, lineWidth: 1).padding(-1)
                            }
                        }
                }
                .padding(.horizontal, spacing / 2)
                .frame(width: pitch)
                .opacity(opacity(bar: bar, isSelected: isSelected, isCurrent: isCurrent, anySelected: selectedWeek != nil))
                .animation(buildAnimation(index: index, count: bars.count), value: isBuilt)
                .animation(waveAnimation(index: index, count: bars.count), value: bar.score)
                .animation(Motion.crossfade, value: pending)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: bar))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { selection = isSelected ? nil : bar.focusDay }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func opacity(bar: WeekBar, isSelected: Bool, isCurrent: Bool, anySelected: Bool) -> Double {
        if anySelected && !isSelected { return 0.4 }
        let isPending = pending == .all || (pending == .today && isCurrent)
        return isPending ? 0.35 : 1
    }

    private func typicalLine(y: CGFloat, width: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y + medalRoom))
            path.addLine(to: CGPoint(x: width, y: y + medalRoom))
        }
        .stroke(Theme.soft.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: width, height: chartHeight + medalRoom)
        .accessibilityHidden(true)
    }

    private func monthLabels(_ bars: [WeekBar], pitch: CGFloat) -> some View {
        let calendar = Calendar.current
        return ZStack(alignment: .topLeading) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                if let first = bar.visibleDays.first(where: { calendar.component(.day, from: $0.date) == 1 }),
                   index < bars.count - 1 {
                    Text(first.date.formatted(.dateTime.month(.abbreviated)))
                        .font(Theme.gridLabel(9.5))
                        .foregroundStyle(Theme.soft)
                        .fixedSize()
                        .offset(x: CGFloat(index) * pitch)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(at x: CGFloat, pitch: CGFloat, in bars: [WeekBar]) -> WeekBar? {
        let index = Int((x / pitch).rounded(.down))
        guard bars.indices.contains(index), !bars[index].visibleDays.isEmpty else { return nil }
        return bars[index]
    }

    private func scrub(pitch: CGFloat, bars: [WeekBar], selectedWeek: WeekBar?) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag?) = value,
                      let bar = bar(at: drag.location.x, pitch: pitch, in: bars),
                      bar.id != selectedWeek?.id else { return }
                selection = bar.focusDay
            }
    }

    /// Off-screen-equivalent of the grid: the year grows left to right within one build beat.
    private func buildAnimation(index: Int, count: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let position = Double(index) / Double(max(count - 1, 1))
        return .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.35).delay(position * (Motion.build - 0.3))
    }

    /// Filter changes ripple in from the newest week.
    private func waveAnimation(index: Int, count: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let fromRight = Double(count - 1 - index)
        return .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.3).delay(min(fromRight, 30) * 0.012)
    }

    private func accessibilityLabel(for bar: WeekBar) -> String {
        let start = (bar.visibleDays.first?.date ?? bar.week.start).formatted(.dateTime.month(.wide).day())
        guard bar.workouts > 0 else { return "Week of \(start), rest week" }
        var text = "Week of \(start), \(bar.workouts) workout\(bar.workouts == 1 ? "" : "s"), "
            + "\(Format.duration(bar.duration)), level \(bar.level) of 4"
        if bar.hasPR { text += ", personal record" }
        return text
    }
}

/// The selected week's seven days, so any of them can be opened from the skyline.
private struct WeekStrip: View {
    let bar: WeekBar
    @Binding var selection: HeatmapDay?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week of \((bar.visibleDays.first?.date ?? bar.week.start).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(Theme.text(13, weight: 700))
                    .foregroundStyle(Theme.ink)
                Text("\(bar.workouts) workout\(bar.workouts == 1 ? "" : "s") · \(Format.duration(bar.duration))")
                    .font(Theme.data(11))
                    .foregroundStyle(Theme.soft)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(bar.week.days) { day in
                    let isSelected = selection?.id == day.id
                    Button { selection = day } label: {
                        VStack(spacing: 3) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(Theme.gridLabel())
                                .foregroundStyle(Theme.soft)
                            HeatmapCell(level: day.level, hasPR: day.hasPR, isVisible: day.isVisible,
                                        isSelected: isSelected, size: 18)
                        }
                        .frame(minWidth: 22, minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!day.isVisible)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
                                        + (day.volume == nil ? ", rest day" : ", level \(day.level) of 4")
                                        + (day.hasPR ? ", personal record" : ""))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .transition(.opacity.combined(with: .offset(y: -4)))
    }
}

/// Key for the dashed "typical week" line, shown beside the section caption.
struct TypicalWeekKey: View {
    var body: some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: 14, y: 0.5))
            }
            .stroke(Theme.soft.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: 14, height: 1)
            Text("TYPICAL")
                .font(Theme.label())
                .tracking(0.8)
                .foregroundStyle(Theme.soft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dashed line: a typical training week")
    }
}

/// Ink-capsule switch between the day grid and the weekly skyline, styled like the filter chips.
struct YearStylePicker: View {
    @Binding var selection: YearStyle
    @Namespace private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(YearStyle.allCases) { style in
                let isOn = selection == style
                Button {
                    withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.32)) {
                        selection = style
                    }
                } label: {
                    Image(systemName: style.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.paper : Theme.soft)
                        .frame(width: 34, height: 26)
                        .background {
                            if isOn { Capsule().fill(Theme.ink).matchedGeometryEffect(id: "ink", in: ink) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1.5))
        .frame(minHeight: 44)
        .contentShape(.rect)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Year view")
    }
}
