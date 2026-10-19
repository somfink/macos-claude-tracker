import AppKit
import ApplicationServices
import CoreGraphics
import os
import TrackerCore

/// Jumps to the Warp tab running a given Claude Code session.
///
/// Warp has no API for this, so it is assembled from what it does expose:
/// 1. the quake ("hotkey") window is shown by synthesizing its own shortcut, read from
///    Warp's defaults (activating via NSWorkspace would make Warp open a *new* window);
/// 2. the window title is the active tab's title, which Claude Code sets to the session title;
/// 3. the Tab → "Switch to Next Tab" menu item is pressed through Accessibility until the
///    title matches.
/// Requires the Accessibility permission (System Settings → Privacy & Security).
@MainActor
enum WarpNavigator {
    static let bundleIdentifier = "dev.warp.Warp-Stable"
    private static let tabMenuTitle = "Tab"
    private static let nextTabItemTitle = "Switch to Next Tab"
    private static let maxTabs = 30
    private static let windowPollInterval: Duration = .milliseconds(50)
    private static let windowWaitAttempts = 30
    /// Quake windows float above normal windows; tiny floating helpers are ignored.
    private static let minQuakeWindowWidth: CGFloat = 200
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "warp")

    static var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    /// Returns false when Warp is not running, so the caller can launch something else.
    static func focus(_ target: TabTarget, among others: [TabTarget]) async -> Bool {
        guard let app = runningApp else { return false }
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            app.activate()
            return true
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        let quakeShown = isQuakeWindowOnScreen(pid: app.processIdentifier)
        let warpActive = app.isActive
        if let hotkey = quakeHotkey(), hotkey.shouldPress(windowOnScreen: quakeShown, warpActive: warpActive) {
            post(hotkey)
        }
        app.activate()
        logger.debug("Jump: quake shown \(quakeShown), Warp active \(warpActive)")

        let hasWindow = await waitForFocusedWindow(element)
        guard !Task.isCancelled else { return true }
        guard hasWindow else {
            logger.info("No focused Warp window after activation")
            return true
        }
        let found = await TabCycler.cycle(
            to: target,
            among: others,
            maxTabs: maxTabs,
            currentTitle: { focusedWindowTitle(element) },
            nextTab: {
                let pressed = pressMenuItem(element, menu: tabMenuTitle, item: nextTabItemTitle)
                logger.debug("Jump: next tab from '\(focusedWindowTitle(element) ?? "-", privacy: .private)', pressed \(pressed)")
                return pressed
            }
        )
        logger.debug("Jump: found \(found), on '\(focusedWindowTitle(element) ?? "-", privacy: .private)'")
        if !found, !Task.isCancelled {
            let stoppedOn = focusedWindowTitle(element) ?? "-"
            logger.info("No Warp tab for \(target.exactTitles, privacy: .private), stopped on '\(stoppedOn, privacy: .private)'")
        }
        return true
    }

    // MARK: Quake window

    private static func quakeHotkey() -> WarpHotkey? {
        guard let defaults = UserDefaults(suiteName: bundleIdentifier),
              defaults.bool(forKey: "QuakeModeEnabled"),
              let json = defaults.string(forKey: "QuakeModeSettings")
        else { return nil }
        return WarpHotkey.parse(quakeSettingsJSON: json)
    }

    private static func isQuakeWindowOnScreen(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"]
            else { return false }
            return width >= minQuakeWindowWidth
        }
    }

    private static func post(_ hotkey: WarpHotkey) {
        guard let keyCode = hotkey.keyCode else {
            logger.error("Cannot synthesize Warp hotkey '\(hotkey.key)'")
            return
        }
        let modifiers: [(Bool, CGEventFlags)] = [
            (hotkey.control, .maskControl),
            (hotkey.option, .maskAlternate),
            (hotkey.shift, .maskShift),
            (hotkey.command, .maskCommand),
        ]
        let flags = modifiers.filter(\.0).reduce(CGEventFlags()) { $0.union($1.1) }
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Accessibility

    private static func requestAccessibilityPermission() {
        // Literal key: the kAXTrustedCheckOptionPrompt global is not concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func waitForFocusedWindow(_ app: AXUIElement) async -> Bool {
        for _ in 0..<windowWaitAttempts {
            if focusedWindowTitle(app) != nil { return true }
            try? await Task.sleep(for: windowPollInterval)
        }
        return false
    }

    private static func focusedWindowTitle(_ app: AXUIElement) -> String? {
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) else { return nil }
        return attribute(window, kAXTitleAttribute)
    }

    private static func pressMenuItem(_ app: AXUIElement, menu: String, item: String) -> Bool {
        guard let menuBar: AXUIElement = attribute(app, kAXMenuBarAttribute),
              let menuBarItem = children(of: menuBar).first(where: { title(of: $0) == menu }),
              let menuElement = children(of: menuBarItem).first,
              let target = children(of: menuElement).first(where: { title(of: $0) == item })
        else { return false }
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }

    private static func title(of element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
