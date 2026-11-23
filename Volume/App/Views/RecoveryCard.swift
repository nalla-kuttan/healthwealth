import SwiftUI
import VolumeCore
import VolumeUI

/// The five readiness bars. Tapping a group selects it for the "why" card below.
struct RecoveryCard: View {
    let recovery: [MuscleReadiness]
    var selected: MuscleGroup?
    var onSelect: (MuscleGroup) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Muscle groups").font(Theme.heading()).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("last 96 h").font(Theme.data(11, weight: 500)).foregroundStyle(Theme.soft)
            }
            .padding(.bottom, 4)
            ForEach(Array(recovery.enumerated()), id: \.element.id) { index, item in
                let isSelected = selected == item.group
                Button { onSelect(item.group) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.group.displayName).font(Theme.text(14, weight: 700)).foregroundStyle(Theme.ink)
                            Spacer()
                            HStack(spacing: 0) {
                                CountUp(item.readiness, duration: 0.6)
                                Text("%")
                            }
                            .font(Theme.data(13, weight: 500))
                            .foregroundStyle(Theme.ink)
                        }
                        ReadinessBar(readiness: item.readiness, height: 7, delay: 0.25 + 0.08 * Double(index))
                        HStack {
                            // Status is always a word and a mark as well as a colour.
                            Text("\(item.status.mark) \(item.status.title)")
                                .font(Theme.text(12, weight: 700))
                                .foregroundStyle(item.status.color)
                            Spacer()
                            if let last = item.lastLoaded {
                                Text("Loaded \(Format.hoursAgo(last))")
                                    .font(Theme.data(11))
                                    .foregroundStyle(Theme.soft)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(isSelected ? Theme.sunk : .clear, in: .rect(cornerRadius: 10))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 1.5)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.group.displayName), \(item.readiness) percent ready, \(item.status.title)")
                .accessibilityHint("Shows which workouts are behind this score")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(Motion.crossfade, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .card()
    }
}

/// "Monday's lift has no name…" prompt that jumps to the day so it can be tagged.
struct UntaggedLiftNudge: View {
    let lifts: [WorkoutRecord]
    let onTap: (WorkoutRecord) -> Void

    var body: some View {
        if let lift = lifts.first {
            Button { onTap(lift) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("◐").foregroundStyle(Theme.intaglio)
                    Text(message(for: lift))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text("Tag it ›").font(Theme.text(13, weight: 700)).foregroundStyle(Theme.intaglio)
                }
                .font(Theme.text(13))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunk, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    private func message(for lift: WorkoutRecord) -> String {
        let when = lift.start.formatted(.dateTime.weekday(.wide))
        let others = lifts.count - 1
        let extra = others > 0 ? " (and \(others) more)" : ""
        return "\(when)'s lift has no name\(extra), so it counts as full body."
    }
}
