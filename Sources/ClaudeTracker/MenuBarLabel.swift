import AppKit
import SwiftUI
import TrackerCore

/// Menu bar item like `💬1  ⚡3  ✓4`. Zero counts are hidden; no sessions shows a lone sparkle.
///
/// MenuBarExtra labels drop SF Symbols interpolated into Text, so the counters are rendered
/// into a template NSImage, which the menu bar tints for light/dark like any system item.
struct MenuBarLabel: View {
    private static let fontSize: CGFloat = 13
    private static let fallbackScale: CGFloat = 2

    let summary: StatusSummary

    private var segments: [(symbol: String, count: Int)] {
        [
            (ActivityStyle.waitingSymbol, summary.waiting),
            (ActivityStyle.workingSymbol, summary.working),
            (ActivityStyle.readySymbol, summary.ready),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        if segments.isEmpty {
            Image(systemName: "sparkle")
        } else {
            Image(nsImage: Self.render(segments))
        }
    }

    @MainActor
    private static func render(_ segments: [(symbol: String, count: Int)]) -> NSImage {
        let content = HStack(spacing: 7) {
            ForEach(segments, id: \.symbol) { segment in
                HStack(spacing: 2) {
                    Image(systemName: segment.symbol)
                    Text("\(segment.count)").monospacedDigit()
                }
            }
        }
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? fallbackScale
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
