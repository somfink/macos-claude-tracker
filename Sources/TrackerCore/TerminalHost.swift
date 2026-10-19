import Darwin
import Foundation

/// The terminal app a session runs in, as far as jumping to it is concerned.
public enum TerminalApp: Equatable, Sendable {
    case warp
    case iTerm2
    case appleTerminal
    /// Any other app: it can be brought forward, but not told which tab to show.
    case other(bundleIdentifier: String)

    public init(bundleIdentifier: String) {
        switch bundleIdentifier {
        case let id where id.hasPrefix("dev.warp.Warp"): self = .warp
        case "com.googlecode.iterm2": self = .iTerm2
        case "com.apple.Terminal": self = .appleTerminal
        default: self = .other(bundleIdentifier: bundleIdentifier)
        }
    }

    public var bundleIdentifier: String? {
        switch self {
        case .warp: nil
        case .iTerm2: "com.googlecode.iterm2"
        case .appleTerminal: "com.apple.Terminal"
        case .other(let id): id
        }
    }
}

public struct ProcessNode: Equatable, Sendable {
    public let parent: Int32
    public let executablePath: String?

    public init(parent: Int32, executablePath: String?) {
        self.parent = parent
        self.executablePath = executablePath
    }
}

/// Walks a session's process ancestry up to the first process that lives inside an app bundle:
/// `claude → zsh → Warp.app/Contents/MacOS/stable` is Warp.
public enum TerminalHost {
    private static let maxDepth = 32

    public static func app(
        hosting pid: Int32,
        node: (Int32) -> ProcessNode?,
        bundleIdentifier: (String) -> String?
    ) -> TerminalApp? {
        // The session process itself is skipped: a claude binary shipped inside some app
        // says nothing about the terminal it was started from.
        var current = node(pid)?.parent
        var visited: Set<Int32> = [pid]
        while let pid = current, pid > 1, visited.count <= maxDepth, visited.insert(pid).inserted {
            guard let process = node(pid) else { return nil }
            if let path = process.executablePath,
               let bundle = appBundlePath(ofExecutable: path),
               let identifier = bundleIdentifier(bundle) {
                return TerminalApp(bundleIdentifier: identifier)
            }
            current = process.parent
        }
        return nil
    }

    /// `/Applications/Warp.app/Contents/MacOS/stable` → `/Applications/Warp.app`. The outermost
    /// bundle wins, so helpers nested inside an app count as the app.
    public static func appBundlePath(ofExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

/// AppleScript that brings forward the iTerm2 session or Terminal.app tab attached to a tty.
public enum TerminalScript {
    /// nil for terminals without a scripting API, or when `tty` is not a plain tty device path:
    /// it is spliced into script source, so nothing else may get through.
    public static func select(tty: String, in app: TerminalApp) -> String? {
        guard isTTYPath(tty) else { return nil }
        switch app {
        case .iTerm2:
            return """
            tell application id "com.googlecode.iterm2"
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if tty of aSession is "\(tty)" then
                                select aWindow
                                select aTab
                                select aSession
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        case .appleTerminal:
            return """
            tell application id "com.apple.Terminal"
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        if tty of aTab is "\(tty)" then
                            set selected of aTab to true
                            set index of aWindow to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case .warp, .other:
            return nil
        }
    }

    private static func isTTYPath(_ value: String) -> Bool {
        let prefix = "/dev/ttys"
        guard value.hasPrefix(prefix) else { return false }
        let digits = value.dropFirst(prefix.count)
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Reads the live process table (parent, executable, controlling terminal).
public enum SystemProcessTable {
    public static func node(of pid: Int32) -> ProcessNode? {
        guard let info = kinfo(of: pid) else { return nil }
        return ProcessNode(parent: info.kp_eproc.e_ppid, executablePath: executablePath(of: pid))
    }

    /// `/dev/ttys003` for a process attached to a terminal, nil otherwise.
    public static func tty(of pid: Int32) -> String? {
        guard let info = kinfo(of: pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func kinfo(of pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
