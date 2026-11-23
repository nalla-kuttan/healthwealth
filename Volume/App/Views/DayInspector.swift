import SwiftUI
import VolumeCore
import VolumeUI

/// Floating summary for a tapped heatmap cell: date, workouts, duration, calories and PRs.
struct DayInspector: View {
    let day: HeatmapDay
    let workouts: [WorkoutRecord]
    let onClose: () -> Void
    /// Tags a strength workout with a body-part day; nil clears the tag.
    var onTag: (WorkoutRecord, StrengthSplit?) -> Void = { _, _ in }

    var body: some View {
        // The card stays put; only its content crossfades when another day is tapped.
        ZStack(alignment: .topLeading) {
            content
                .id(day.id)
                .transition(.opacity)
        }
        .animation(Motion.crossfade, value: day.id)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rule))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.soft)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1.5))
                }
                .accessibilityLabel("Close")
            }

            if let volume = day.volume {
                Text("\(volume.workoutIDs.count) workout\(volume.workoutIDs.count == 1 ? "" : "s") · \(Format.duration(volume.duration)) · \(Int(volume.energyKcal.rounded())) kcal")
                    .font(Theme.data(12))
                    .foregroundStyle(Theme.soft)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workouts) { workout in
                        VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: workout.kind.symbolName)
                                .frame(width: 20)
                                .foregroundStyle(Theme.intaglio)
                            VStack(alignment: .leading, spacing: 1) {
                                nameLabel(for: workout)
                                // The name you gave it in Hevy/Strong, when it adds something.
                                if let subtitle = subtitle(for: workout) {
                                    Text(subtitle).font(Theme.data(11)).foregroundStyle(Theme.soft).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(detail(for: workout))
                                .font(Theme.data(12))
                                .foregroundStyle(Theme.soft)
                                .monospacedDigit()
                        }
                        if let lift = workout.lift, !lift.exercises.isEmpty {
                            ExerciseList(lift: lift).padding(.leading, 30)
                        }
                        if workout.needsSplitTag {
                            DayTagPicker { onTag(workout, $0) }
                                .padding(.leading, 30)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        }
                    }
                }
                .animation(Motion.crossfade, value: workouts.map(\.strengthSplit))

                ForEach(day.personalRecords) { pr in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        MedalMark()
                            .stampIn(delay: 0.12)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(pr.headline) · \(pr.valueText)")
                                .font(Theme.text(14, weight: 700))
                                .foregroundStyle(Theme.ink)
                            Text(pr.improvementText).font(Theme.data(11)).foregroundStyle(Theme.rose)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Personal record. \(pr.headline), \(pr.valueText), \(pr.improvementText)")
                }
            } else {
                Text("Rest day · no workouts")
                    .font(Theme.data(12))
                    .foregroundStyle(Theme.soft)
            }
        }
    }

    private func name(for workout: WorkoutRecord) -> String {
        if workout.kind.isStrength, workout.strengthSplit != .unknown { return workout.strengthSplit.displayName }
        if workout.kind == .multisport, let title = workout.title { return title }
        return workout.kind.displayName
    }

    /// Strength sessions get a menu on their name so a tag can be set, changed or cleared.
    @ViewBuilder
    private func nameLabel(for workout: WorkoutRecord) -> some View {
        let label = Text(name(for: workout)).font(Theme.text(14)).foregroundStyle(Theme.ink)
        if workout.kind.isStrength && !workout.needsSplitTag {
            Menu {
                ForEach(StrengthSplit.bodyParts, id: \.self) { split in
                    Button { onTag(workout, split) } label: {
                        if workout.strengthSplit == split { Label(split.displayName, systemImage: "checkmark") }
                        else { Text(split.displayName) }
                    }
                }
                if workout.splitTag != nil {
                    Divider()
                    Button("Use the workout's name", systemImage: "arrow.uturn.backward") { onTag(workout, nil) }
                }
            } label: {
                HStack(spacing: 4) {
                    label
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.soft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes which day this workout counts as")
        } else {
            label
        }
    }

    private func subtitle(for workout: WorkoutRecord) -> String? {
        guard workout.kind.isStrength, let title = workout.title, !title.isEmpty,
              title.caseInsensitiveCompare(name(for: workout)) != .orderedSame else { return nil }
        return title
    }

    private func detail(for workout: WorkoutRecord) -> String {
        var parts = [Format.duration(workout.duration)]
        if let meters = workout.distanceMeters { parts.append(Format.distance(meters)) }
        parts.append("\(Int(workout.activeEnergyKcal.rounded())) kcal")
        return parts.joined(separator: " · ")
    }
}

/// "Which day was this?" with one chip per body-part day, for lifts saved without a usable name.
private struct DayTagPicker: View {
    let onPick: (StrengthSplit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which day was this? Untagged lifts count as full body.")
                .font(Theme.text(12))
                .foregroundStyle(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StrengthSplit.bodyParts, id: \.self) { split in
                        Button(split.displayName) { onPick(split) }
                            .font(Theme.text(12, weight: 700))
                            .foregroundStyle(Theme.intaglio)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Theme.intaglio.opacity(0.45), lineWidth: 1.5))
                            .contentShape(.capsule)
                            .accessibilityLabel("Tag as \(split.displayName) day")
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
    }
}

/// Exercises from a Hevy import: "Bench Press (Barbell)   3 × 8 · top 80 kg".
private struct ExerciseList: View {
    let lift: LiftDetail
    private let limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lift.exercises.prefix(limit).enumerated()), id: \.offset) { _, exercise in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(exercise.name).font(Theme.text(12)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(exercise.summary).font(Theme.data(11)).foregroundStyle(Theme.soft).monospacedDigit()
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
            if lift.exercises.count > limit {
                Text("+\(lift.exercises.count - limit) more · \(lift.workingSets) working sets")
                    .font(Theme.data(11))
                    .foregroundStyle(Theme.soft)
            }
        }
    }
}
