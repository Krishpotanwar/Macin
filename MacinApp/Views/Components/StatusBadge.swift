// StatusBadge.swift — Colored pill badge for status display
import SwiftUI

struct StatusBadge: View {
    let status: DownloadStatus

    var body: some View {
        Text(status.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.accentColor.opacity(0.25))
            .foregroundColor(status.accentColor)
            .clipShape(Capsule())
    }
}
