import SwiftUI
import TrackerCore

/// Pixel crab for one session row, animated while its mood calls for it.
///
/// TimelineView only ticks while the panel is on screen, so closed panels cost nothing.
struct MascotView: View {
    /// 1.5× the sprite: 3 device pixels per sprite pixel on Retina, still perfectly sharp.
    private static let zoom: CGFloat = 1.5
    private static let renderer = MascotRenderer()

    let mood: MascotMood

    var body: some View {
        if let interval = mood.frameInterval {
            TimelineView(.periodic(from: .now, by: interval)) { context in
                frame(Int(context.date.timeIntervalSinceReferenceDate / interval))
            }
        } else {
            frame(0)
        }
    }

    @ViewBuilder
    private func frame(_ index: Int) -> some View {
        if let image = Self.renderer.frame(index, of: mood) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: image.size.width * Self.zoom, height: image.size.height * Self.zoom)
                .accessibilityLabel(Text(mood.rawValue))
        }
    }
}
