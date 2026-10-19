import AppKit
import TrackerCore

/// Brings the terminal running a Claude Code session to the front.
@MainActor
enum TerminalActivator {
    /// Launched when no supported terminal is running. First installed wins.
    static let fallbackBundleIdentifiers = [
        WarpNavigator.bundleIdentifier,
        "com.apple.Terminal",
    ]

    /// The tab walk in progress; a newer click replaces it so two walks never switch tabs at once.
    private static var navigation: Task<Void, Never>?

    /// Warp: show its window (quake window included) and switch to the session's tab.
    /// Otherwise launch the first installed terminal.
    static func focus(_ tab: (target: TabTarget, others: [TabTarget])) {
        closeMenuPanel()
        navigation?.cancel()
        navigation = Task {
            if await WarpNavigator.focus(tab.target, among: tab.others) { return }
            guard !Task.isCancelled else { return }
            launchFallback()
        }
    }

    /// The menu bar panel would otherwise stay open on top of the terminal it just switched to.
    /// It is the key window when a row is clicked; a click on a notification or the widget
    /// finds no panel open and closes nothing. Closing the window directly leaves SwiftUI
    /// believing the panel is still shown (the next click on the icon does nothing), so the
    /// status item's own button is clicked instead, the same path as closing it by hand.
    private static func closeMenuPanel() {
        guard let panel = NSApp.keyWindow as? NSPanel else { return }
        let statusButton = NSApp.windows
            .filter { $0.className == "NSStatusBarWindow" }
            .lazy
            .compactMap { $0.contentView.flatMap(firstButton) }
            .first
        if let statusButton {
            statusButton.performClick(nil)
        } else {
            panel.close()
        }
    }

    private static func firstButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap(firstButton).first
    }

    private static func launchFallback() {
        let workspace = NSWorkspace.shared
        guard let appURL = fallbackBundleIdentifiers.lazy.compactMap(workspace.urlForApplication).first else { return }
        workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
