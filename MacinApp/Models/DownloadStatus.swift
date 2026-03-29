// DownloadStatus.swift — Status enum with color + icon helpers
import SwiftUI

enum DownloadStatus: String, Codable, CaseIterable, Sendable {
    case waiting, downloading, paused, completed, failed

    var accentColor: Color {
        switch self {
        case .waiting:     .gray
        case .downloading: .blue
        case .paused:      .orange
        case .completed:   .green
        case .failed:      .red
        }
    }

    var sfSymbol: String {
        switch self {
        case .waiting:     "clock"
        case .downloading: "arrow.down.circle.fill"
        case .paused:      "pause.circle.fill"
        case .completed:   "checkmark.circle.fill"
        case .failed:      "xmark.circle.fill"
        }
    }

    var label: String { rawValue.capitalized }
}
