import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VolumeCore
import VolumeUI

/// Behind the gear on the Year tab. Few settings on purpose: Volume works without any.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("yearAsList") private var yearAsList = false
    @State private var confirmsClear = false
    @State private var importsHevy = false
    @State private var confirmsRemoveHevy = false
    @State private var hevyMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show the year as a list", isOn: $yearAsList)
                        .tint(Theme.intaglio)
                } header: {
                    Text("Display")
                } footer: {
                    Text("A day-by-day list instead of the grid. Easier with VoiceOver and turns on by itself at the largest text sizes.")
                }
                .listRowBackground(Theme.card)

                Section {
                    if model.hevySessions.isEmpty {
                        Button("Import Hevy export…") { importsHevy = true }
                    } else {
                        let summary = model.hevyMatchSummary
                        LabeledContent("Hevy workouts", value: "\(model.hevySessions.count)")
                        LabeledContent("Matched to Health", value: "\(summary.matched)")
                        LabeledContent("Added from Hevy history", value: "\(summary.added)")
                        if let date = model.hevyImportedAt {
                            LabeledContent("Imported", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button("Import a newer export…") { importsHevy = true }
                        Button("Remove Hevy data", role: .destructive) { confirmsRemoveHevy = true }
                    }
                    if let hevyMessage {
                        Text(hevyMessage).font(Theme.text(13)).foregroundStyle(Theme.soft)
                    }
                } header: {
                    Text("Hevy")
                } footer: {
                    Text("Sets, reps and weights make recovery follow the muscles you actually trained and add lift PRs. In Hevy: Profile › Settings › Export & Import Data › Export Data › Export Workouts, save it to Files, then import it here. The file stays on this iPhone.")
                }
                .listRowBackground(Theme.card)

                Section {
                    LabeledContent("Days you've tagged", value: "\(model.splitTags.count)")
                    Button("Clear all tags", role: .destructive) { confirmsClear = true }
                        .disabled(model.splitTags.isEmpty)
                } header: {
                    Text("Workout days")
                } footer: {
                    Text("Volume reads chest, back, shoulders, arms or legs from the name Hevy or Strong saves. Tag a lift yourself by tapping its day on the heatmap.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Manage Health access") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Volume reads workouts, active energy, distance and heart rate. It never writes to Health, and nothing leaves this iPhone.")
                }
                .listRowBackground(Theme.card)

                Section("Widgets") {
                    ForEach(Array(WidgetSteps.all.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)").font(Theme.title(15)).foregroundStyle(Theme.intaglio)
                            Text(step)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Button("Show the introduction again") {
                        dismiss()
                        model.resetIntroduction()
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Type: Archivo and Atkinson Hyperlegible, both under the SIL Open Font License.")
                }
                .listRowBackground(Theme.card)
            }
            .font(Theme.text(15))
            .foregroundStyle(Theme.ink)
            .listRowSeparatorTint(Theme.rule)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Theme.text(16, weight: 700)).foregroundStyle(Theme.ink)
                }
            }
            .fileImporter(isPresented: $importsHevy, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url):
                    do {
                        let count = try model.importHevy(from: url)
                        hevyMessage = "Imported \(count) workouts from Hevy."
                    } catch {
                        hevyMessage = error.localizedDescription
                    }
                case .failure(let error):
                    hevyMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Remove Hevy data?", isPresented: $confirmsRemoveHevy, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.removeHevyImport()
                    hevyMessage = nil
                }
            } message: {
                Text("Sets and weights from the import are removed from Volume. Your Hevy account and the file aren't touched.")
            }
            .confirmationDialog("Clear all \(model.splitTags.count) tags?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear tags", role: .destructive) { model.clearAllTags() }
            } message: {
                Text("Lifts go back to the day read from their name, or full body if they have none.")
            }
        }
        .presentationBackground(Theme.paper)
    }
}

enum WidgetSteps {
    static let all = [
        "Touch and hold an empty spot on the Home Screen until the icons jiggle.",
        "Tap Edit, then Add Widget, and search for Volume.",
        "Pick medium (16 weeks + streak) or large (20 weeks + recovery), then Add Widget.",
    ]
}
