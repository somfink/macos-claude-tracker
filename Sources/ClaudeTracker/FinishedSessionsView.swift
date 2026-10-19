import AppKit
import SwiftUI
import TrackerCore

/// "Zakończone dziś" tab: sessions whose process ended today, newest first.
/// Clicking one copies the command that resumes it in its folder.
struct FinishedSessionsView: View {
    private static let copiedFeedback: Duration = .seconds(2)

    let sessions: [FinishedSession]
    let isSnapshot: Bool

    @State private var copiedId: String?

    var body: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "Nic jeszcze dziś nie skończyło",
                systemImage: "checkmark.seal",
                description: Text("Zamknięte dziś sesje pojawią się tutaj z ostatnią odpowiedzią.")
            )
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kliknij, aby skopiować polecenie wznowienia sesji")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                PanelList(isSnapshot: isSnapshot) {
                    ForEach(sessions) { session in
                        FinishedRow(session: session, isCopied: copiedId == session.id) { copy(session) }
                    }
                }
            }
        }
    }

    private func copy(_ session: FinishedSession) {
        guard let command = session.resumeCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedId = session.id
        Task {
            try? await Task.sleep(for: Self.copiedFeedback)
            if copiedId == session.id { copiedId = nil }
        }
    }
}

private struct FinishedRow: View {
    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)

    let session: FinishedSession
    let isCopied: Bool
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MascotView(mood: .sleeping)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(isCopied ? "Skopiowano" : "zakończona")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                Text(session.endedAt.formatted(Self.timeFormat))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                if let cost = session.cost {
                    Text(UsageFormat.usd(cost))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onCopy)
        .help(session.resumeCommand ?? session.sessionId)
        .contextMenu {
            Button("Kopiuj polecenie wznowienia", action: onCopy)
            if let cwd = session.cwd {
                Button("Pokaż folder w Finderze") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: cwd)])
                }
            }
        }
    }

    private var subtitle: String {
        [session.title == session.project ? nil : session.project, session.summary]
            .compactMap { $0 }
            .joined(separator: " — ")
    }
}
