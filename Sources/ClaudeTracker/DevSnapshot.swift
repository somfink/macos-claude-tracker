import AppKit
import os
import SwiftUI
import TrackerCore

/// Dev aid for checking visuals without capturing the screen:
/// - `CLAUDE_TRACKER_SNAPSHOT=/path/dash.png` renders the dashboard with live data,
/// - `CLAUDE_TRACKER_MASCOT_SNAPSHOT=/path/mascot.png` renders every mascot frame enlarged
///   on dark and light menu bar backgrounds,
/// - `CLAUDE_TRACKER_ICON=/path/icon.png` renders the 1024 px app icon master.
/// Each writes the PNG and exits.
@MainActor
enum DevSnapshot {
    static let dashboardKey = "CLAUDE_TRACKER_SNAPSHOT"
    static let mascotKey = "CLAUDE_TRACKER_MASCOT_SNAPSHOT"
    static let iconKey = "CLAUDE_TRACKER_ICON"
    /// `active` (default), `finished` or `costs`.
    static let tabKey = "CLAUDE_TRACKER_SNAPSHOT_TAB"
    private static let mascotZoom: CGFloat = 8

    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment[dashboardKey] {
            let store = SessionStore()
            store.refresh()
            let usage = UsageMonitor()
            usage.refreshRateLimits()
            usage.apply(waitFor { await usage.scanner.scan(roots: store.roots, sessionIds: store.snapshot.sessions.map(\.sessionId)) })
            let tab = environment[tabKey].flatMap(DashboardTab.init(rawValue:)) ?? .active
            write(DashboardView(store: store, usage: usage, isSnapshot: true, forcedTab: tab)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark), to: path)
        }
        if let path = environment[mascotKey] {
            write(mascotSheet, to: path)
        }
        if let path = environment[iconKey] {
            writeAppIcon(to: path)
        }
    }

    /// 1024 px master for `scripts/make-icon.sh`: the crab on a dark rounded square, laid out
    /// on Apple's icon grid (824 px tile, 100 px margin), pixels drawn as hard squares.
    private static func writeAppIcon(to path: String) {
        let canvas = 1024
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            FileHandle.standardError.write(Data("Icon bitmap could not be created\n".utf8))
            exit(1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()

        let sprite = MascotSprites.appIcon
        // The crab spans 16 of the sprite's 20 columns; it fills most of the tile so it still
        // reads at the 32 px a notification banner shows.
        let crabColumns: CGFloat = 16
        let pixel = (tile.width * 0.8 / crabColumns).rounded(.down)
        let origin = CGPoint(
            x: tile.midX - pixel * CGFloat(sprite.width) / 2,
            y: tile.midY + pixel * CGFloat(sprite.height) / 2
        )
        context.shouldAntialias = false
        for (row, line) in sprite.rows.enumerated() {
            for (column, character) in line.enumerated() {
                guard let color = MascotRenderer.palette[character] else { continue }
                color.setFill()
                CGRect(x: origin.x + CGFloat(column) * pixel, y: origin.y - CGFloat(row + 1) * pixel, width: pixel, height: pixel).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        do {
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: URL(filePath: path))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Icon write failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static var mascotSheet: some View {
        let renderer = MascotRenderer()
        return VStack(spacing: 0) {
            ForEach([Color(white: 0.12), Color(white: 0.93)], id: \.self) { background in
                HStack(spacing: 24) {
                    ForEach(MascotMood.allCases, id: \.self) { mood in
                        ForEach(Array((renderer.frames[mood] ?? []).enumerated()), id: \.offset) { _, image in
                            Image(nsImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: image.size.width * mascotZoom, height: image.size.height * mascotZoom)
                        }
                    }
                }
                .padding(24)
                .background(background)
            }
        }
    }

    /// Blocks app launch until `work` finishes; acceptable only in this dev-only path.
    private static func waitFor<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let box = OSAllocatedUnfairLock<T?>(initialState: nil)
        Task.detached {
            let value = await work()
            box.withLock { $0 = value }
        }
        while true {
            if let value = box.withLock({ $0 }) { return value }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func write(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("Snapshot rendering failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(filePath: path))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Snapshot write failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
