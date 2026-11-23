import SwiftUI
import VolumeUI

enum MainTab: Hashable { case year, recovery }

/// Two tabs, one per question: "How consistent have I been?" and "What's ready to train today?"
struct MainTabView: View {
    @State private var tab: MainTab = .year

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(tab: $tab)
                .tabItem { Label("Year", systemImage: "square.grid.3x3.fill") }
                .tag(MainTab.year)
            RecoveryView(tab: $tab)
                .tabItem { Label("Recovery", systemImage: "figure.strengthtraining.traditional") }
                .tag(MainTab.recovery)
        }
        .tint(Theme.ink)
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: tab)
    }
}
