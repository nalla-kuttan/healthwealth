import SwiftUI
import VolumeCore
import VolumeUI

/// 7 × 52–53 contribution grid, auto-scrolled to the current week. Columns are weeks, rows are
/// weekdays in the user's locale order.
struct HeatmapView: View {
    /// Cells still being delivered by Health are drawn faded.
    enum Pending { case none, today, all }

    let grid: HeatmapGrid
    @Binding var selection: HeatmapDay?
    var pending: Pending = .none
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until the year has inked in on first appearance.
    @State private var isBuilt = false

    private let cell: CGFloat = 14
    private let spacing: CGFloat = 3
    private let monthRowHeight: CGFloat = 14
    private var pitch: CGFloat { cell + spacing }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            weekdayLabels
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels
                        columns
                    }
                    // Room for the selection and today outlines, which sit outside the cell.
                    .padding(.horizontal, 3)
                    .padding(.bottom, 3)
                }
                .defaultScrollAnchor(.trailing)
                .onChange(of: grid.weeks.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .trailing) }
                }
                .task {
                    guard !isBuilt else { return }
                    if !reduceMotion { try? await Task.sleep(for: .milliseconds(150)) }
                    isBuilt = true
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection?.id)
    }

    /// The whole grid is one touch surface: a tap picks the nearest cell (gaps included), and
    /// touch-and-hold then slide scrubs from cell to cell.
    private var columns: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(grid.weeks.enumerated()), id: \.element.id) { index, week in
                column(week, index: index)
            }
        }
        .contentShape(.rect)
        .onTapGesture(coordinateSpace: .local) { location in
            guard let day = day(at: location) else { return }
            selection = selection?.id == day.id ? nil : day
        }
        .gesture(scrub)
        .accessibilityElement(children: .contain)
        .accessibilityRotor(Text("Weeks"), entries: weekStarts, entryID: \.id, entryLabel: \.weekRotorLabel)
        .accessibilityRotor(Text("Personal records"), entries: prDays, entryID: \.id, entryLabel: \.dayRotorLabel)
    }

    private func column(_ week: HeatmapWeek, index: Int) -> some View {
        let signature: [Int] = week.days.map { $0.level * 2 + ($0.hasPR ? 1 : 0) }
        return VStack(spacing: spacing) {
            ForEach(week.days) { day in cellView(day) }
        }
        // The year inks in left to right; filter changes ripple across as a wave.
        .animation(buildAnimation(column: index), value: isBuilt)
        .animation(waveAnimation(column: index), value: signature)
        .animation(Motion.crossfade, value: pending)
        .id(week.id)
    }

    /// First visible day of each week, newest week first (rotor stops).
    private var weekStarts: [HeatmapDay] {
        grid.weeks.reversed().compactMap { week in week.days.first(where: \.isVisible) }
    }

    private var prDays: [HeatmapDay] {
        let days: [HeatmapDay] = grid.visibleDays.filter(\.hasPR)
        return days.reversed()
    }


    /// Touch and hold, then slide: the selection follows the finger.
    private var scrub: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag?) = value, let day = day(at: drag.location),
                      day.id != selection?.id else { return }
                selection = day
            }
    }

    private func day(at point: CGPoint) -> HeatmapDay? {
        let column = Int((point.x / pitch).rounded(.down))
        let row = Int((point.y / pitch).rounded(.down))
        guard grid.weeks.indices.contains(column) else { return nil }
        let days = grid.weeks[column].days
        guard days.indices.contains(row), days[row].isVisible else { return nil }
        return days[row]
    }

    /// Columns off-screen to the left ink at once; the visible ~24 weeks sweep in within 900 ms.
    private func buildAnimation(column: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let visible = 24.0
        let position = max(0, Double(column) - (Double(grid.weeks.count) - visible)) / visible
        return .easeOut(duration: 0.2).delay(position * (Motion.build - 0.2))
    }

    private func waveAnimation(column: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let fromRight = Double(grid.weeks.count - 1 - column)
        return Motion.crossfade.delay(min(fromRight, 30) * 0.012)
    }


    private func isPending(_ day: HeatmapDay) -> Bool {
        switch pending {
        case .none: false
        case .today: day.date == grid.today
        case .all: true
        }
    }

    private var weekdayLabels: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return VStack(alignment: .trailing, spacing: spacing) {
            Color.clear.frame(height: monthRowHeight)
            ForEach(Array(grid.weekdayOrder.enumerated()), id: \.offset) { index, weekday in
                // Label every other row, like GitHub, to keep the gutter quiet.
                Text(index.isMultiple(of: 2) ? "" : symbols[weekday - 1])
                    .font(Theme.gridLabel())
                    .foregroundStyle(Theme.soft)
                    .frame(height: cell)
            }
        }
        .frame(width: 12)
        .padding(.top, 4 - spacing)
    }

    private var monthLabels: some View {
        let calendar = Calendar.current
        return HStack(spacing: spacing) {
            ForEach(Array(grid.weeks.enumerated()), id: \.element.id) { index, week in
                let firstOfMonth = week.days.first { calendar.component(.day, from: $0.date) == 1 && $0.isVisible }
                let label = firstOfMonth.map { $0.date.formatted(.dateTime.month(.abbreviated)) }
                    ?? (index == 0 ? week.days.first(where: \.isVisible)?.date.formatted(.dateTime.month(.abbreviated)) : nil)
                Color.clear
                    .frame(width: cell, height: monthRowHeight)
                    .overlay(alignment: .leading) {
                        if let label {
                            Text(label)
                                .font(Theme.gridLabel(9.5))
                                .foregroundStyle(Theme.soft)
                                .fixedSize()
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: HeatmapDay) -> some View {
        let isSelected = selection?.id == day.id
        let isToday = day.date == grid.today
        HeatmapCell(level: isBuilt ? day.level : 0, hasPR: isBuilt && day.hasPR, isVisible: day.isVisible,
                    isSelected: isSelected, isToday: isToday, size: cell)
            .opacity(isPending(day) && day.isVisible ? 0.35 : 1)
            .scaleEffect(isSelected && !reduceMotion ? 1.15 : 1)
            .animation(Motion.stamp, value: isSelected)
            .overlay {
                if isToday && isBuilt { TodayBeat(size: cell, cornerRadius: cell * 0.23) }
            }
            .zIndex(isSelected ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(!day.isVisible)
            .accessibilityLabel(accessibilityLabel(for: day))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = isSelected ? nil : day }
            .id(day.id)
    }

    private func accessibilityLabel(for day: HeatmapDay) -> String {
        let date = day.date.formatted(date: .complete, time: .omitted)
        guard let volume = day.volume else { return "\(date), rest day" }
        var text = "\(date), \(volume.workoutIDs.count) workouts, \(Format.duration(volume.duration)), level \(day.level) of 4"
        if day.hasPR { text += ", personal record" }
        return text
    }
}

private extension HeatmapDay {
    var weekRotorLabel: String { "Week of \(date.formatted(.dateTime.month(.wide).day()))" }
    var dayRotorLabel: String { date.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
}
