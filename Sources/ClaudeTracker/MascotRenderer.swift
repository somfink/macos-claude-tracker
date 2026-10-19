import AppKit
import TrackerCore

/// Turns sprite frames into crisp NSImages, once, at launch.
@MainActor
struct MascotRenderer {
    /// One sprite pixel = 1 pt = 2 device pixels on Retina: sharp edges, 20×16 pt icon.
    static let pixelSize: CGFloat = 1

    static let palette: [Character: NSColor] = MascotPalette.colors.mapValues { rgb in
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    let frames: [MascotMood: [NSImage]]

    init() {
        frames = Dictionary(uniqueKeysWithValues: MascotMood.allCases.map { mood in
            (mood, MascotSprites.frames(for: mood).map(Self.image))
        })
    }

    func frame(_ index: Int, of mood: MascotMood) -> NSImage? {
        guard let moodFrames = frames[mood], !moodFrames.isEmpty else { return nil }
        return moodFrames[index % moodFrames.count]
    }

    static func image(for sprite: PixelSprite) -> NSImage {
        let size = NSSize(width: CGFloat(sprite.width) * pixelSize, height: CGFloat(sprite.height) * pixelSize)
        let image = NSImage(size: size, flipped: true) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            for (y, row) in sprite.rows.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = palette[char] else { continue }
                    color.setFill()
                    NSRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize, width: pixelSize, height: pixelSize).fill()
                }
            }
            return true
        }
        // Colored art: the menu bar must not flatten it into a monochrome template.
        image.isTemplate = false
        return image
    }
}
