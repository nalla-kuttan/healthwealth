import SwiftUI
import UIKit
import VolumeUI

/// Shown when HealthKit is unavailable on this device or the authorization request failed.
struct HealthAccessView: View {
    enum Reason {
        case unavailable
        case failed(String)
    }

    let reason: Reason
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GuillocheRosette()
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity)
                    .riseIn(0)
                Text(title).font(Theme.title(26)).foregroundStyle(Theme.ink)
                Text(message).font(Theme.text(16)).foregroundStyle(Theme.soft)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(Theme.title(20))
                                .foregroundStyle(Theme.intaglio)
                                .frame(width: 28, alignment: .leading)
                            Text(step).font(Theme.text(15)).foregroundStyle(Theme.ink)
                        }
                    }
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open Settings")
                        .font(Theme.text(16, weight: 700))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Theme.onRose)
                        .background(Theme.rose, in: .capsule)
                }

                Button("Try again") { Task { await model.retry() } }
                    .font(Theme.text(15, weight: 700))
                    .foregroundStyle(Theme.intaglio)
                    .frame(maxWidth: .infinity)

                Label("Volume only reads workouts. Everything is analyzed on this device and never uploaded.",
                      systemImage: "lock.shield")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.soft)
            }
            .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
    }

    private var title: String {
        switch reason {
        case .unavailable: "Health data isn't available"
        case .failed: "Allow access to workouts"
        }
    }

    private var message: String {
        switch reason {
        case .unavailable:
            "This device can't read Apple Health. On iPad, Health data appears once Health sync is turned on for your iCloud account."
        case .failed(let error):
            "Volume needs read access to your workouts to build your heatmap. (\(error))"
        }
    }

    private var steps: [String] {
        switch reason {
        case .unavailable:
            ["Open Settings › [your name] › iCloud and turn on Health.",
             "Open the Health app on this device and wait for your data to sync.",
             "Come back and tap Try again."]
        case .failed:
            ["Open Settings › Health › Data Access & Devices.",
             "Choose Volume and turn on Workouts, Active Energy, Distance and Heart Rate.",
             "Come back and tap Try again."]
        }
    }
}
