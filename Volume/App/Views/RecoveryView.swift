import Charts
import SwiftUI
import VolumeCore
import VolumeUI

/// Recovery tab: the lowest group as the one big number, the five bars, and a "why" card that
/// lists the workouts behind the selected score and plots its recovery forward.
struct RecoveryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: MuscleGroup?
    @Binding var tab: MainTab

    private let recoveryModel = RecoveryModel()

    var body: some View {
        // Readiness keeps decaying while the app is open; refresh every five minutes.
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let now = context.date
            let events = model.analysis?.strainEvents ?? []
            let recovery = recoveryModel.readiness(events: events, at: now)
            let lowest = recovery.min { $0.readiness < $1.readiness }
            let focus = selected ?? lowest?.group ?? .legs

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(now: now)
                    if let lowest {
                        Summary(recovery: recovery, lowest: lowest).riseIn(0)
                    }
                    RecoveryCard(recovery: recovery, selected: focus) { selected = $0 }.riseIn(1)
                    UntaggedLiftNudge(lifts: model.untaggedRecentLifts) { lift in
                        model.selectedDay = model.heatmapDay(for: lift)
                        tab = .year
                    }
                    if let item = recovery.first(where: { $0.group == focus }) {
                        WhyCard(item: item,
                                contributions: recoveryModel.contributions(for: focus, events: events, at: now),
                                forecast: recoveryModel.forecast(for: focus, events: events, from: now),
                                name: workoutName)
                            .riseIn(2)
                            .id(focus)
                            .transition(.opacity)
                    }
                    Text("Readiness is an estimate from each workout's load and type, not a medical measure.")
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.soft)
                }
                .animation(Motion.crossfade, value: focus)
                .id(dynamicTypeSize)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .refreshable { await model.sync() }
        }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()).uppercased())
                .font(Theme.label())
                .tracking(0.8)
                .foregroundStyle(Theme.soft)
            Text("Recovery")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func workoutName(_ id: String, kind: ActivityKind) -> String {
        guard let workout = model.workout(id: id) else { return kind.displayName }
        if workout.needsSplitTag { return "Untagged lift" }
        if workout.kind.isStrength, workout.strengthSplit != .unknown { return workout.strengthSplit.displayName }
        return workout.kind.displayName
    }
}

// MARK: - Summary

private struct Summary: View {
    let recovery: [MuscleReadiness]
    let lowest: MuscleReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                HStack(spacing: 0) {
                    CountUp(lowest.readiness)
                    Text("%")
                }
                .font(Theme.denomination())
                .foregroundStyle(Theme.ink)
                Text("lowest").font(Theme.text(14, weight: 600)).foregroundStyle(Theme.soft)
            }
            .accessibilityElement(children: .combine)
            Text(sentence)
                .font(Theme.text(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Voice: "Legs: rest recommended. Chest, back and arms are ready."
    private var sentence: String {
        let ready = recovery.filter { $0.status == .primed }.map(\.group.displayName)
        if ready.count == recovery.count { return "Everything is ready. Train whatever you like today." }
        let first: String = switch lowest.status {
        case .highStrain: "\(lowest.group.displayName): rest recommended."
        case .recovering: "\(lowest.group.displayName): still recovering."
        case .primed: ""
        }
        guard !ready.isEmpty else { return first + " Nothing is fully ready yet." }
        let list = ListFormatter.localizedString(byJoining: ready.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() })
        return "\(first) \(list) \(ready.count == 1 ? "is" : "are") ready."
    }
}

// MARK: - Why card

private struct WhyCard: View {
    let item: MuscleReadiness
    let contributions: [StrainContribution]
    let forecast: RecoveryForecast
    let name: (String, ActivityKind) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why \(item.group.displayName) is at \(item.readiness)%")
                .font(Theme.heading())
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)

            if contributions.isEmpty {
                Text("No workouts loaded \(item.group.displayName.lowercased()) in the last 96 hours.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.soft)
            } else {
                VStack(spacing: 6) {
                    ForEach(contributions) { part in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(name(part.workoutID, part.kind)) · \(Format.hoursAgo(part.date))")
                                .font(Theme.text(13))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("−\(part.points)")
                                .font(Theme.data(13, weight: 500))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(name(part.workoutID, part.kind)), \(Format.hoursAgo(part.date)), takes off \(part.points) points")
                    }
                }
                ForecastChart(forecast: forecast)
                    .frame(height: 132)
                    .accessibilityElement()
                    .accessibilityLabel("Readiness for \(item.group.displayName) over the next four days")
                    .accessibilityValue(forecastText)
            }
            Text(forecastText)
                .font(Theme.text(13, weight: 700))
                .foregroundStyle(item.status == .primed ? Theme.ok : Theme.ink)
        }
        .card()
    }

    /// "Recovering by Thursday evening, primed by Friday morning."
    private var forecastText: String {
        switch (forecast.recoveringAt, forecast.primedAt) {
        case let (recovering?, primed?): "Recovering by \(When.phrase(recovering)), primed by \(When.phrase(primed))."
        case let (nil, primed?): "Ready again around \(When.phrase(primed))."
        default: "Ready to train."
        }
    }
}

private struct ForecastChart: View {
    let forecast: RecoveryForecast

    var body: some View {
        Chart {
            RuleMark(y: .value("Primed", 76))
                .foregroundStyle(Theme.ok.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Primed 76").font(Theme.data(9)).foregroundStyle(Theme.soft)
                }
            RuleMark(y: .value("Recovering", 45))
                .foregroundStyle(Theme.warn.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Recovering 45").font(Theme.data(9)).foregroundStyle(Theme.soft)
                }
            ForEach(forecast.points, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Floor", 0), yEnd: .value("Readiness", point.readiness))
                    .foregroundStyle(Theme.intaglio.opacity(0.12))
                LineMark(x: .value("Time", point.date), y: .value("Readiness", point.readiness))
                    .foregroundStyle(Theme.intaglio)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let first = forecast.points.first {
                PointMark(x: .value("Now", first.date), y: .value("Readiness", first.readiness))
                    .foregroundStyle(Theme.rose)
                    .symbolSize(40)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(Theme.rule)
                AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(Theme.data(10)).foregroundStyle(Theme.soft)
            }
        }
    }
}

/// "this evening", "tomorrow morning", "Friday afternoon".
enum When {
    static func phrase(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        if calendar.isDate(date, inSameDayAs: now) { return "this \(part)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow \(part)" }
        return "\(date.formatted(.dateTime.weekday(.wide))) \(part)"
    }
}
