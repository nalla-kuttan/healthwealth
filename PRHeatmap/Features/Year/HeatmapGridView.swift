import SwiftUI

/// 7 × 53 contribution grid. Opens anchored on the current week (trailing edge).
struct HeatmapGridView: View {
    let model: HeatmapModel
    let selectedDate: Date?
    var revealedWeeks: Int = .max
    var onSelect: (DayCell) -> Void

    private let size = Theme.cellSize
    private let gap = Theme.cellGap
    private let monthRowHeight: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            weekdayColumn
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(model.weeks) { week in
                        VStack(alignment: .leading, spacing: gap) {
                            Text(week.monthLabel ?? " ")
                                .font(Theme.gridLabel)
                                .foregroundStyle(Theme.soft)
                                .fixedSize()
                                .frame(width: size, height: monthRowHeight, alignment: .leading)
                            ForEach(week.days) { day in
                                DayCellView(
                                    day: day,
                                    isSelected: day.date == selectedDate,
                                    isPending: week.index >= revealedWeeks
                                )
                                .onTapGesture { onSelect(day) }
                            }
                        }
                        .id(week.index)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 3)
            }
            .defaultScrollAnchor(.trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Training heatmap, last 52 weeks")
    }

    private var weekdayColumn: some View {
        VStack(alignment: .trailing, spacing: gap) {
            Color.clear.frame(width: 8, height: monthRowHeight)
            ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                // Label every other row, like a contribution graph.
                Text(index.isMultiple(of: 2) ? " " : symbol)
                    .font(Theme.gridLabel)
                    .foregroundStyle(Theme.soft)
                    .frame(width: 8, height: size)
            }
        }
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}

struct DayCellView: View {
    let day: DayCell
    var isSelected = false
    var isPending = false
    var size: CGFloat = Theme.cellSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cellRadius * size / Theme.cellSize, style: .continuous)
        shape
            .fill(Theme.volume(day.level))
            .overlay {
                if day.isPR {
                    // Medal ring: rose outside, a paper gap, then the volume ink.
                    shape.strokeBorder(Theme.paper, lineWidth: size * 0.245)
                    shape.strokeBorder(Theme.rose, lineWidth: size * 0.145)
                }
            }
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    shape.stroke(Theme.ink, lineWidth: 2).padding(-2)
                } else if day.isToday {
                    shape.stroke(Theme.soft, lineWidth: 1.5).padding(-1.5)
                }
            }
            .opacity(day.isFuture ? 0 : (isPending ? 0.35 : 1))
            .contentShape(Rectangle().inset(by: -Theme.cellGap / 2))
            .accessibilityElement()
            .accessibilityHidden(day.isFuture)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        var parts = [Format.accessibleDate(day.date)]
        if day.workouts.isEmpty {
            parts.append("rest day")
        } else {
            parts.append("level \(day.level.rawValue) of 4")
            parts.append("\(day.workouts.count) workout\(day.workouts.count == 1 ? "" : "s")")
        }
        if day.isPR { parts.append("personal record") }
        if day.isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }
}
