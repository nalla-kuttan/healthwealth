import SwiftUI
import VolumeCore
import VolumeUI

/// First run, before the system permission sheet: what Volume is, then exactly what it reads.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var isConnecting = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if step == 0 {
                intro.transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                scopes.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.4), value: step)
    }

    // MARK: Step 1 — welcome

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 8)
            GuillocheRosette()
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)
                .riseIn(0)
            VStack(alignment: .leading, spacing: 10) {
                Text("VOLUME").font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.soft)
                Text("Every session leaves a mark.")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your year of training, drawn from Apple Health without logging a single set. The darker the day, the harder you trained. A rose ring marks a record.")
                    .font(Theme.text(16))
                    .foregroundStyle(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .riseIn(1)
            SampleYear().riseIn(2)
            Spacer(minLength: 8)
            Button { step = 1 } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle())
            .riseIn(3)
        }
        .padding(24)
    }

    // MARK: Step 2 — read scopes

    private var scopes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("READ-ONLY · ON-DEVICE").font(Theme.label(11)).tracking(1).foregroundStyle(Theme.soft)
                    Text("See your whole year of training")
                        .font(Theme.title(28))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Volume asks Apple Health for these five things. iOS shows the switches next.")
                        .font(Theme.text(15))
                        .foregroundStyle(Theme.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    scope("Workouts", "type, time, length, name")
                    scope("Active energy", "kcal")
                    scope("Walking + running distance", "km")
                    scope("Cycling distance", "km")
                    scope("Heart rate", "for training load + PRs")
                }
                .paperCard(padding: 14)
                Label("Nothing leaves this iPhone. Volume never writes to Health.", systemImage: "lock.shield")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.ink)
                PulseRule(isLive: isConnecting)
                Button {
                    isConnecting = true
                    Task { await model.finishWelcome() }
                } label: {
                    Text("Connect Apple Health").frame(maxWidth: .infinity)
                }
                .buttonStyle(RoseButtonStyle())
                .disabled(isConnecting)
                Button("Back") { step = 0 }
                    .font(Theme.text(15, weight: 700))
                    .foregroundStyle(Theme.intaglio)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private func scope(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(Theme.text(15)).foregroundStyle(Theme.ink)
            Spacer()
            Text(detail).font(Theme.data(11)).foregroundStyle(Theme.soft).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// A sample 20-week grid so the payoff is visible before any permission is asked.
private struct SampleYear: View {
    private let weeks: [[WidgetSnapshot.Day]] = WidgetSnapshot(analysis: TrainingAnalysis.compute(records: DemoData.records())).weeks

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CompactHeatmap(weeks: weeks, spacing: 3, background: Theme.paper)
                .frame(height: 100)
            Text("Example year").font(Theme.data(10)).foregroundStyle(Theme.soft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example heatmap: twenty weeks of training, darker days were harder, rose rings mark records")
    }
}

/// The one main action on a screen: rose, full width.
struct RoseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(16, weight: 700))
            .padding(.vertical, 15)
            .foregroundStyle(Theme.onRose)
            .background(Theme.rose, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.crossfade, value: configuration.isPressed)
    }
}

/// Secondary full-width action: ink capsule.
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(16, weight: 700))
            .padding(.vertical, 15)
            .foregroundStyle(Theme.paper)
            .background(Theme.ink, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.crossfade, value: configuration.isPressed)
    }
}
