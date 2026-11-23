#if DEBUG
import SwiftUI
import VolumeCore
import VolumeUI

/// Debug-only (`-widgetGallery`): renders the widget layouts at iPhone 17 Pro widget sizes from
/// the same snapshot the extension reads, so they can be checked without SpringBoard.
struct WidgetGalleryView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                frame(width: 364, height: 170) { MediumWidgetView(snapshot: snapshot) }
                frame(width: 364, height: 382) {
                    LargeWidgetView(snapshot: snapshot, recovery: snapshot.recovery(at: .now))
                }
                AccessoryWidgetView(snapshot: snapshot, recovery: snapshot.recovery(at: .now))
                    .frame(width: 172, height: 76)
                    .padding(8)
                    .background(.black.opacity(0.8), in: .rect(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
    }

    private func frame<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(Theme.card, in: .rect(cornerRadius: 24, style: .continuous))
    }
}
#endif
