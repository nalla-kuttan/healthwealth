import SwiftUI
import VolumeCore
import WidgetKit

/// Widget layouts live here (not in the extension) so the app can render them in a debug gallery.
/// No animation and no colour beyond the ink ramp and rose: widgets must read at arm's length.

private struct StreakBadge: View {
    let streak: Int
    let workoutsThisWeek: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(streak)")
                .font(Theme.denomination(36))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(streak == 1 ? "week\nstreak" : "weeks\nstreak")
                .font(Theme.text(11))
                .foregroundStyle(Theme.soft)
                .fixedSize()
            Spacer(minLength: 0)
            Text("\(workoutsThisWeek) this week")
                .font(Theme.data(10, weight: 500))
                .foregroundStyle(Theme.soft)
                .fixedSize()
        }
    }
}

private struct EmptyWidgetLabel: View {
    var body: some View {
        Text("Record a workout to start your heatmap")
            .font(Theme.text(12, weight: 700))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(8)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule))
    }
}

/// systemMedium: 16-week heatmap + weekly streak.
public struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot
    let showsEmptyState: Bool

    public init(snapshot: WidgetSnapshot, showsEmptyState: Bool = true) {
        self.snapshot = snapshot
        self.showsEmptyState = showsEmptyState
    }

    public var body: some View {
        HStack(spacing: 14) {
            StreakBadge(streak: snapshot.weeklyStreak, workoutsThisWeek: snapshot.workoutsThisWeek)
                .frame(width: 70, alignment: .leading)
            CompactHeatmap(weeks: Array(snapshot.weeks.suffix(16)), spacing: 3)
        }
        .overlay { if showsEmptyState && !snapshot.hasAnyWorkouts { EmptyWidgetLabel() } }
    }
}

/// systemLarge: 20-week heatmap + all five muscle-group readiness bars.
public struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot
    let recovery: [MuscleReadiness]
    let showsEmptyState: Bool

    public init(snapshot: WidgetSnapshot, recovery: [MuscleReadiness], showsEmptyState: Bool = true) {
        self.snapshot = snapshot
        self.recovery = recovery
        self.showsEmptyState = showsEmptyState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("20 weeks").font(Theme.heading(15)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(snapshot.weeklyStreak)-week streak")
                    .font(Theme.data(11, weight: 500))
                    .foregroundStyle(Theme.soft)
            }
            CompactHeatmap(weeks: snapshot.weeks, spacing: 3)
                .frame(height: 122)
                .overlay { if showsEmptyState && !snapshot.hasAnyWorkouts { EmptyWidgetLabel() } }
            VStack(spacing: 8) {
                ForEach(recovery) { item in
                    VStack(spacing: 3) {
                        HStack {
                            Text(item.group.displayName).font(Theme.text(12, weight: 700))
                            Spacer()
                            Text("\(item.status.mark) \(item.readiness)%")
                                .font(Theme.data(12, weight: 500))
                                .monospacedDigit()
                                .foregroundStyle(item.status.color)
                        }
                        .foregroundStyle(Theme.ink)
                        ReadinessBar(readiness: item.readiness, height: 5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Lock Screen (accessoryRectangular): streak plus the most fatigued muscle group.
/// Uses the system's vibrant styling, so only the fonts follow the theme.
public struct AccessoryWidgetView: View {
    let snapshot: WidgetSnapshot
    let recovery: [MuscleReadiness]

    public init(snapshot: WidgetSnapshot, recovery: [MuscleReadiness]) {
        self.snapshot = snapshot
        self.recovery = recovery
    }

    public var body: some View {
        let mostTired = recovery.min { $0.readiness < $1.readiness }
        VStack(alignment: .leading, spacing: 1) {
            Text("\(snapshot.weeklyStreak)-week streak")
                .font(Theme.heading(15))
                .widgetAccentable()
            if let mostTired {
                Text("\(mostTired.group.shortName) \(mostTired.readiness)% · \(mostTired.status.title)")
                    .font(Theme.text(12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
