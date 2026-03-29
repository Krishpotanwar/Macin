// SpeedLabel.swift — Fixed-width speed display that prevents layout jitter
import SwiftUI

struct SpeedLabel: View {
    let bytesPerSecond: Double
    let status: DownloadStatus

    private var label: String {
        guard status == .downloading, bytesPerSecond > 0 else { return "—" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(bytesPerSecond),
            countStyle: .file
        ) + "/s"
    }

    var body: some View {
        Text(label)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 80, alignment: .leading)
            .animation(Theme.springAnimation, value: bytesPerSecond)
    }
}
