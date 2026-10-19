import AppKit
import SwiftUI
import TrackerCore

struct SessionRowView: View {
    private static let unreadDotSize: CGFloat = 7

    let session: TrackedSession
    let title: String
    let summary: String?
    let isUnread: Bool
    let cost: Double?
    let contextPercentage: Double?
    /// Working but nothing written since then (see `Stall`).
    let stalledSince: Date?
    let showAccount: Bool
    let now: Date
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MascotView(mood: MascotMood(activity: session.activity))

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(ActivityText.label(for: session.activity))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ActivityStyle.color(for: session.activity))
                    .lineLimit(1)
                if let stalledSince {
                    Label("bez postępu \(RelativeAge.format(stalledSince, now: now))", systemImage: "hourglass")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help("Status „pracuje”, ale od tego czasu nic nie trafiło do transkryptu. Długie polecenia też tak wyglądają.")
                } else if let since = session.statusSince {
                    Text(RelativeAge.format(since, now: now))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                usageLine

            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .help(summary.map { "\(session.cwd)\n\n\($0)" } ?? session.cwd)
        .contextMenu {
            Button("Przejdź do terminala", action: onOpen)
            Divider()
            Button("Pokaż folder w Finderze") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: session.cwd)])
            }
            Button("Kopiuj ścieżkę") { copy(session.cwd) }
            Button("Kopiuj ID sesji") { copy(session.sessionId) }
        }
    }

    private static let contextWarningPercentage = 80.0

    /// `$14.98 · ctx 28%`; context turns orange when the window is nearly full.
    @ViewBuilder
    private var usageLine: some View {
        if cost != nil || contextPercentage != nil {
            HStack(spacing: 3) {
                if let cost {
                    Text(UsageFormat.usd(cost))
                        .foregroundStyle(.tertiary)
                        .help("Koszt sesji według cennika API (z subagentami)")
                }
                if cost != nil, contextPercentage != nil {
                    Text("·").foregroundStyle(.tertiary)
                }
                if let contextPercentage {
                    Text("ctx \(Int(contextPercentage.rounded()))%")
                        .foregroundStyle(contextPercentage >= Self.contextWarningPercentage ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                        .help("Zajętość okna kontekstu (ze statusline)")
                }
            }
            .font(.caption2)
            .monospacedDigit()
        }
    }

    private var titleLine: some View {
        HStack(spacing: 5) {
            if isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: Self.unreadDotSize, height: Self.unreadDotSize)
                    .accessibilityLabel("Nowy wynik")
            }
            Text(title)
                .font(.system(size: 13, weight: isUnread ? .bold : .semibold))
                .lineLimit(1)
        }
    }

    /// Project folder when the title is not the folder, account when several are open,
    /// then the last answer.
    private var subtitle: String? {
        let parts = [
            title == session.projectName ? nil : session.projectName,
            showAccount ? session.account : nil,
            summary,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
