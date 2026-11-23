import SwiftUI
import VolumeCore

public protocol HeatmapCellRepresentable: Hashable {
    var level: Int { get }
    var hasPR: Bool { get }
    var isVisible: Bool { get }
}

extension HeatmapDay: HeatmapCellRepresentable {}
extension WidgetSnapshot.Day: HeatmapCellRepresentable {}

/// Heatmap colours, kept as a thin alias over `Theme` for existing call sites.
public enum HeatmapPalette {
    /// Intaglio blue: volume ink and interactive accents.
    public static let accent = Theme.intaglio
    /// Rose: personal records only.
    public static let pr = Theme.rose

    public static func color(level: Int) -> Color { Theme.volume(level: level) }
}

public struct HeatmapCell: View {
    var level: Int
    var hasPR: Bool
    var isVisible: Bool
    var isSelected: Bool
    var isToday: Bool
    var size: CGFloat
    var background: Color

    /// - Parameter background: the surface behind the grid; the PR ring's inner gap uses it.
    public init(level: Int, hasPR: Bool, isVisible: Bool = true, isSelected: Bool = false, isToday: Bool = false,
                size: CGFloat, background: Color = Theme.paper) {
        self.level = level
        self.hasPR = hasPR
        self.isVisible = isVisible
        self.isSelected = isSelected
        self.isToday = isToday
        self.size = size
        self.background = background
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
        shape
            .fill(isVisible ? Theme.volume(level: level) : .clear)
            .overlay {
                if hasPR && isVisible {
                    // Medal ring: rose outside, a gap in the background colour, then the ink.
                    ZStack {
                        shape.strokeBorder(background, lineWidth: max(1.6, size * 0.25))
                        shape.strokeBorder(Theme.rose, lineWidth: max(1.1, size * 0.15))
                    }
                    .transition(.stamp)
                }
            }
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    shape.stroke(Theme.ink, lineWidth: 2).padding(-2)
                } else if isToday && isVisible {
                    shape.stroke(Theme.soft, lineWidth: 1.5).padding(-1.5)
                }
            }
    }
}

/// Size-to-fit grid for widgets: as many square cells as fit the proposed space.
public struct CompactHeatmap<Day: HeatmapCellRepresentable>: View {
    var weeks: [[Day]]
    var spacing: CGFloat
    var background: Color

    public init(weeks: [[Day]], spacing: CGFloat = 3, background: Color = Theme.card) {
        self.weeks = weeks
        self.spacing = spacing
        self.background = background
    }

    public var body: some View {
        GeometryReader { geo in
            let columns = CGFloat(max(weeks.count, 1))
            let size = max(2, min((geo.size.width - spacing * (columns - 1)) / columns,
                                  (geo.size.height - spacing * 6) / 7))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(weeks.indices, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(weeks[column].indices, id: \.self) { row in
                            let day = weeks[column][row]
                            HeatmapCell(level: day.level, hasPR: day.hasPR, isVisible: day.isVisible,
                                        size: size, background: background)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

public struct HeatmapLegend: View {
    var background: Color
    public init(background: Color = Theme.paper) { self.background = background }

    public var body: some View {
        HStack(spacing: 6) {
            Text("Rest")
            HStack(spacing: 3) {
                ForEach(0..<5) { HeatmapCell(level: $0, hasPR: false, size: 10) }
            }
            Text("Peak")
            Spacer(minLength: 12)
            HeatmapCell(level: 2, hasPR: true, size: 10, background: background)
            Text("PR")
        }
        .font(Theme.text(11))
        .foregroundStyle(Theme.soft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lighter cells are rest days, darker cells are harder days. A rose ring marks a personal record.")
    }
}

public extension ReadinessStatus {
    var color: Color {
        switch self {
        case .primed: Theme.ok
        case .recovering: Theme.warn
        case .highStrain: Theme.crit
        }
    }

    /// Shape cue so status never depends on colour alone.
    var mark: String {
        switch self {
        case .primed: "✓"
        case .recovering: "◐"
        case .highStrain: "!"
        }
    }
}

public struct ReadinessBar: View {
    var readiness: Int
    var height: CGFloat
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?

    /// Fills from zero to `readiness` on first appearance (after `delay`), then glides on changes.
    public init(readiness: Int, height: CGFloat = 8, delay: Double = 0) {
        self.readiness = readiness
        self.height = height
        self.delay = delay
    }

    public var body: some View {
        let value = shown ?? (reduceMotion ? Double(readiness) : 0)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sunk)
                Capsule()
                    .fill(ReadinessStatus(readiness: readiness).color)
                    .frame(width: max(height, geo.size.width * CGFloat(value) / 100))
                    .opacity(value == 0 ? 0 : 1)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .onAppear {
            guard shown == nil else { return }
            withAnimation(reduceMotion ? nil : Motion.fill.delay(delay)) { shown = Double(readiness) }
        }
        .onChange(of: readiness) { _, new in
            withAnimation(reduceMotion ? nil : Motion.fill) { shown = Double(new) }
        }
    }
}
