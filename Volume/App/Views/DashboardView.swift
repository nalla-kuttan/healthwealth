import SwiftUI
import VolumeCore
import VolumeUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @AppStorage("yearAsList") private var yearAsList = false
    @Binding var tab: MainTab
    @State private var showsSettings = false
    @State private var shareImage: Image?

    /// Screen-reader and very large text users get the list; everyone else can opt in from Settings.
    private var showsList: Bool { yearAsList || dynamicTypeSize >= .accessibility1 }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Header(isSyncing: model.isSyncing, beat: model.newWorkoutBeat, shareImage: shareImage) {
                        showsSettings = true
                    }
                    if let analysis = model.analysis {
                        SummaryRow(analysis: analysis).riseIn(0)
                        FilterChips(selection: $model.filter).riseIn(1)
                        if showsList {
                            HeatmapListView(grid: analysis.grid, selection: $model.selectedDay).riseIn(1)
                        } else {
                            HeatmapSection(analysis: analysis, selection: $model.selectedDay,
                                           isSyncing: model.isSyncing, isBackfilling: model.isBackfilling)
                                .riseIn(1)
                        }
                        if model.showsWidgetOffer && !model.widgetOfferDismissed {
                            WidgetOfferCard(snapshot: WidgetSnapshot(analysis: analysis)) {
                                withAnimation(Motion.crossfade) { model.dismissWidgetOffer() }
                            }
                            .riseIn(2)
                        }
                        PersonalRecordsCard(records: Array(analysis.personalRecords.prefix(5))).riseIn(3)
                        footer(analysis).riseIn(4)
                    }
                }
                // Bundled fonts resolve as UIFonts, so rebuild when the text size setting changes.
                .id(dynamicTypeSize)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, model.selectedDay == nil ? 24 : 280)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.sync() }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .task(id: shareKey) { renderShareCard() }
            .task(id: model.analysis != nil) { await landOnNewestPR() }
        }
        .overlay(alignment: .bottom) {
            if let day = model.selectedDay {
                DayInspector(day: day, workouts: model.workouts(on: day)) {
                    model.selectedDay = nil
                } onTag: { workout, split in
                    model.tag(workout.id, as: split)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Slides in once; tapping another day only crossfades its content (see DayInspector).
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.3), value: model.selectedDay == nil)
        .sensoryFeedback(.success, trigger: model.newPRBeat)
        .sensoryFeedback(.selection, trigger: model.splitTags)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.sync() } }
        }
    }

    private var shareKey: String {
        guard let analysis = model.analysis else { return "" }
        return "\(analysis.filter.rawValue)-\(analysis.totals.workouts)-\(analysis.totals.personalRecords)"
    }

    /// The shareable year card, rendered off-screen whenever the numbers change.
    private func renderShareCard() {
        guard let analysis = model.analysis, analysis.totals.workouts > 0 else { shareImage = nil; return }
        let renderer = ImageRenderer(content: YearCard(analysis: analysis).environment(\.colorScheme, .light))
        renderer.scale = max(displayScale, 2)
        if let image = renderer.uiImage {
            shareImage = Image(uiImage: image)
            #if DEBUG
            // -exportYearCard: also save the card to Documents for checking it off-device.
            if ProcessInfo.processInfo.arguments.contains("-exportYearCard"), let data = image.pngData(),
               let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? data.write(to: docs.appending(path: "year-card.png"))
            }
            #endif
        }
    }

    /// First run: once the year has inked in, select the newest PR so its medal stamps in.
    private func landOnNewestPR() async {
        guard model.landOnNewestPR, let analysis = model.analysis else { return }
        model.landOnNewestPR = false
        try? await Task.sleep(for: .seconds(Motion.build + 0.35))
        guard let newest = analysis.personalRecords.first else { return }
        model.selectedDay = analysis.grid.weeks.lazy.flatMap(\.days)
            .first { Calendar.current.isDate($0.date, inSameDayAs: newest.date) }
    }

    private func footer(_ analysis: TrainingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isDemo {
                Text("Showing demo data (-demoData launch argument)")
            }
            if let error = model.lastSyncError {
                Text("Last sync failed: \(error)").foregroundStyle(Theme.crit)
            }
            Text("Analyzed on-device in \(Int((analysis.computeTime * 1_000).rounded())) ms. Nothing leaves this iPhone.")
        }
        .font(Theme.text(12))
        .foregroundStyle(Theme.soft)
        .padding(.top, 4)
    }
}

// MARK: - Header & summary

private struct Header: View {
    let isSyncing: Bool
    let beat: Int
    let shareImage: Image?
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            // Loading line while syncing; beats once when a new workout lands.
            PulseRule(beat: beat, isLive: isSyncing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isSyncing ? "Syncing with Apple Health" : "")
    }

    private var title: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOLUME · LAST 52 WEEKS")
                    .font(Theme.label())
                    .tracking(0.8)
                    .foregroundStyle(Theme.soft)
                Text("Your year")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            HStack(spacing: 8) {
                if let shareImage {
                    ShareLink(item: shareImage,
                              preview: SharePreview("My year of training", image: shareImage)) {
                        CircleIcon(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share your year")
                }
                Button(action: onSettings) { CircleIcon(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .padding(.bottom, 4)
        }
    }
}

/// 36 pt ruled circle around a symbol, with a 44 pt tap target.
private struct CircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1.5))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

private struct SummaryRow: View {
    let analysis: TrainingAnalysis
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At the largest text sizes the stats move under the big number instead of squeezing it.
        if dynamicTypeSize >= .xxxLarge {
            VStack(alignment: .leading, spacing: 10) {
                denomination
                HStack(alignment: .top, spacing: 18) { stats }
            }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                denomination
                Spacer(minLength: 0)
                stats
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var denomination: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            CountUp(analysis.totals.workouts)
                .font(Theme.denomination())
                .fixedSize()
            Text("workouts")
                .font(Theme.text(14, weight: 600))
                .foregroundStyle(Theme.soft)
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stats: some View {
        stat(analysis.totals.personalRecords, "PRs", color: Theme.rose)
        stat(analysis.weeklyStreak, "wk streak", color: Theme.ink)
        stat(Int((analysis.totals.duration / 3_600).rounded()), "hours", color: Theme.ink)
    }

    private func stat(_ value: Int, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CountUp(value)
                .font(Theme.title(19))
                .foregroundStyle(color)
            Text(label).font(Theme.text(11)).foregroundStyle(Theme.soft)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Filter

private struct FilterChips: View {
    @Binding var selection: ModalityFilter
    @Namespace private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ModalityFilter.allCases) { filter in
                    let isOn = selection == filter
                    Button(filter.title) {
                        withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.32)) {
                            selection = filter
                        }
                    }
                        .font(Theme.text(13, weight: 700))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .foregroundStyle(isOn ? Theme.paper : Theme.ink)
                        .background {
                            // The ink capsule slides from chip to chip.
                            if isOn { Capsule().fill(Theme.ink).matchedGeometryEffect(id: "ink", in: ink) }
                        }
                        .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.rule, lineWidth: 1.5))
                        .contentShape(.capsule)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Sections

extension View {
    /// Paper card with a 1 pt rule (see `PaperCard` in VolumeUI).
    func card() -> some View { paperCard() }
}

private struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.heading()).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail { Text(detail).font(Theme.data(11, weight: 500)).foregroundStyle(Theme.soft) }
        }
    }
}

private struct HeatmapSection: View {
    let analysis: TrainingAnalysis
    @Binding var selection: HeatmapDay?
    var isSyncing = false
    var isBackfilling = false
    @AppStorage("yearStyle") private var style: YearStyle = .days

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(style.caption.uppercased())
                    .font(Theme.label())
                    .tracking(0.8)
                    .foregroundStyle(Theme.soft)
                    .contentTransition(.opacity)
                    .animation(Motion.crossfade, value: style)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if style == .weeks {
                    TypicalWeekKey().padding(.leading, 6).transition(.opacity)
                }
                Spacer(minLength: 8)
                YearStylePicker(selection: $style)
            }
            Group {
                switch style {
                case .days:
                    HeatmapView(grid: analysis.grid, selection: $selection, pending: pending)
                case .weeks:
                    WeeklySkylineView(grid: analysis.grid, selection: $selection, pending: pending)
                }
            }
            .transition(.opacity)
            .overlay {
                if analysis.totals.workouts == 0 { EmptyHeatmapPrompt(filter: analysis.filter) }
            }
            HStack(alignment: .firstTextBaseline) {
                HeatmapLegend()
                Text("\(analysis.totals.activeDays) active days")
                    .font(Theme.data(11, weight: 500))
                    .foregroundStyle(Theme.soft)
                    .fixedSize()
            }
        }
    }
}

extension HeatmapSection {
    /// Faded while Health is still delivering them: everything during the backfill, today otherwise.
    var pending: HeatmapView.Pending {
        if isBackfilling { return .all }
        return isSyncing ? .today : .none
    }
}

private struct EmptyHeatmapPrompt: View {
    let filter: ModalityFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(filter == .all ? "Your year starts with one workout" : "No \(filter.title) workouts this year")
                .font(Theme.heading(15))
                .foregroundStyle(Theme.ink)
            Text(filter == .all
                 ? "Record one on Apple Watch or in the Fitness app. It shows up here on its own."
                 : "Try another filter, or log a \(filter.title.lowercased()) session to start this streak.")
                .font(Theme.text(13))
                .foregroundStyle(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            if filter == .all {
                Button("Already have workouts? Check Health access") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(Theme.text(13, weight: 700))
                .foregroundStyle(Theme.intaglio)
            }
        }
        .paperCard(padding: 14)
        .padding(.horizontal, 12)
    }
}

private struct PersonalRecordsCard: View {
    let records: [PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recent PRs")
            if records.isEmpty {
                Text("PRs appear on their own when you beat a previous best pace, distance, burn rate or training load.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.soft)
            } else {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    HStack(spacing: 12) {
                        MedalMark(size: 20).stampIn(delay: 0.5 + 0.09 * Double(index))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.headline).font(Theme.text(14, weight: 700)).foregroundStyle(Theme.ink)
                            Text(record.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(Theme.data(11))
                                .foregroundStyle(Theme.soft)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(record.valueText)
                                .font(Theme.data(13, weight: 500))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                            Text(record.improvementText).font(Theme.data(11)).foregroundStyle(Theme.rose)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }
}
