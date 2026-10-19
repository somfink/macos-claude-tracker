import SwiftUI
import TrackerCore

/// Color and symbol per activity, shared by the menu bar label, tiles and rows.
enum ActivityStyle {
    static let waitingColor = Color.orange
    static let workingColor = Color.blue
    static let readyColor = Color.green

    static let waitingSymbol = "exclamationmark.bubble.fill"
    static let workingSymbol = "bolt.fill"
    static let readySymbol = "checkmark.circle.fill"
    static let backgroundTaskSymbol = "terminal.fill"
    static let unknownSymbol = "questionmark.circle"

    static func color(for activity: SessionActivity) -> Color {
        switch activity {
        case .waiting: waitingColor
        case .working: workingColor
        case .ready, .backgroundTask: readyColor
        case .unknown: .secondary
        }
    }

    static func symbol(for activity: SessionActivity) -> String {
        switch activity {
        case .waiting: waitingSymbol
        case .working: workingSymbol
        case .ready: readySymbol
        case .backgroundTask: backgroundTaskSymbol
        case .unknown: unknownSymbol
        }
    }
}
