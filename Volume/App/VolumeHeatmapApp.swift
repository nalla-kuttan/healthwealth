import SwiftUI
import UIKit
import VolumeCore
import VolumeUI

@main
struct VolumeHeatmapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // HealthKit background delivery relaunches the app in the background; the observer query
        // has to be re-registered right here for those launches to deliver.
        AppModel.shared.startBackgroundObservation()
        return true
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                VStack(spacing: 20) {
                    GuillocheRosette().frame(maxWidth: 240)
                    PulseRule(isLive: true).frame(maxWidth: 180)
                    Text("Reading Apple Health…").font(Theme.text(15)).foregroundStyle(Theme.soft)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .background(Theme.paper.ignoresSafeArea())
            case .welcome:
                WelcomeView().transition(.opacity)
            case .unavailable:
                HealthAccessView(reason: .unavailable)
            case .authorizationFailed(let message):
                HealthAccessView(reason: .failed(message))
            case .ready:
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-widgetGallery"), let analysis = model.analysis {
                    WidgetGalleryView(snapshot: WidgetSnapshot(analysis: analysis))
                } else {
                    MainTabView()
                }
                #else
                MainTabView()
                #endif
            }
        }
        .animation(Motion.crossfade, value: model.phase)
        .task { await model.start() }
    }
}
