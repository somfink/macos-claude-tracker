import SwiftUI
import TrackerCore

enum DashboardTab: String, CaseIterable {
    case active
    case finished
    case costs
}

/// Panel shown after clicking the menu bar item: header, tabs, the selected tab, footer.
struct DashboardView: View {
    private static let panelWidth: CGFloat = 480

    let store: SessionStore
    let usage: UsageMonitor
    var launchAtLogin: LaunchAtLogin?
    var notifications: NotificationService?
    /// ImageRenderer cannot draw ScrollView content, so snapshots lay rows out flat.
    var isSnapshot = false
    /// Snapshots pick their tab explicitly instead of reading the remembered one.
    var forcedTab: DashboardTab?

    @AppStorage(NotificationService.enabledDefaultsKey) private var notificationsEnabled = true
    @AppStorage("dashboardTab") private var storedTab: DashboardTab = .active

    private var tab: DashboardTab { forcedTab ?? storedTab }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tabPicker
            switch tab {
            case .active:
                ActiveSessionsView(store: store, usage: usage, isSnapshot: isSnapshot)
            case .finished:
                FinishedSessionsView(sessions: usage.finishedToday, isSnapshot: isSnapshot)
            case .costs:
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    CostsView(report: usage.report, now: context.date)
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: Self.panelWidth)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sesje Claude Code").font(.headline)
            Spacer()
            if tab == .active, !store.unread.ids.isEmpty {
                Button("Wszystko przeczytane (\(store.unread.ids.count))") { store.markAllRead() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Text(PolishPlural.active(store.summary.total)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var tabPicker: some View {
        TabBar(
            items: [
                .init(tab: .active, title: "Aktywne (\(store.summary.total))"),
                .init(tab: .finished, title: "Zakończone dziś (\(usage.finishedToday.count))"),
                .init(tab: .costs, title: "Koszty"),
            ],
            selection: $storedTab
        )
    }

    private func launchAtLoginHelp(_ item: LaunchAtLogin) -> String {
        if item.needsApproval { return "Zatwierdź w Ustawienia → Ogólne → Rzeczy otwierane podczas logowania" }
        return item.isEnabled ? "Uruchamia się przy logowaniu (kliknij, by wyłączyć)" : "Uruchamiaj przy logowaniu"
    }

    private var accountsHelp: String {
        let paths = store.roots.map { "\($0.account): \($0.sessionsDirectory.deletingLastPathComponent().path)" }
        return (["Obserwowane katalogi konfiguracji Claude Code (CLAUDE_CONFIG_DIR):"] + paths).joined(separator: "\n")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !store.snapshot.issues.isEmpty {
                Label("\(store.snapshot.issues.count) nieczytelne", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(store.snapshot.issues.map(\.file.lastPathComponent).joined(separator: ", "))
            }
            Text("Konta: \(store.roots.map(\.account).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help(accountsHelp)
            Spacer()
            if let notifications, notifications.blockedBySystem {
                Button {
                    notifications.openSystemSettings()
                } label: {
                    Label("Powiadomienia zablokowane", systemImage: "bell.slash.fill")
                }
                .foregroundStyle(.orange)
                .help("macOS nie pokazuje powiadomień Claude Tracker. Kliknij, by otworzyć Ustawienia → Powiadomienia.")
            } else if notifications != nil {
                Button {
                    notificationsEnabled.toggle()
                } label: {
                    Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash")
                }
                .help(notificationsEnabled ? "Powiadomienia włączone (prawy klik: próbne)" : "Powiadomienia wyłączone")
                .contextMenu {
                    Button("Wyślij próbne powiadomienie") { notifications?.postTest() }
                }
            }
            if let launchAtLogin, launchAtLogin.isAvailable {
                Button {
                    launchAtLogin.toggle()
                } label: {
                    Image(systemName: launchAtLogin.isEnabled ? "power.circle.fill" : "power.circle")
                }
                .help(launchAtLoginHelp(launchAtLogin))
            }
            Button("Odśwież") { store.refresh() }
                .keyboardShortcut("r")
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

/// Scrolls in the live panel; lays rows out flat for offscreen snapshots.
struct PanelList<Content: View>: View {
    static var maxHeight: CGFloat { 520 }

    let isSnapshot: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if isSnapshot {
            VStack(spacing: 2) { content }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) { content }
            }
            .frame(maxHeight: Self.maxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
