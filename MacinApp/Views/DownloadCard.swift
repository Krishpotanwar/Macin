// DownloadCard.swift — Glass card with IDM-style chunk visualization, ETA, and Reveal in Finder
import SwiftUI

struct DownloadCard: View {
    let task: DownloadTask
    let onPause:  () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry:  () -> Void
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            // Glass card background
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                        .stroke(Theme.cardBorder, lineWidth: 0.5)
                )
                .shadow(
                    color: Theme.cardShadow,
                    radius: Theme.cardShadowRadius,
                    y: Theme.cardShadowY
                )

            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(spacing: 8) {
                    Image(systemName: task.status.sfSymbol)
                        .font(.title3)
                        .foregroundColor(task.status.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.filename)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: task.category.sfSymbol)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(destinationLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    StatusBadge(status: task.status)
                }

                // Chunk segment visualization (IDM-style)
                if task.status == .downloading || task.status == .paused {
                    ChunkProgressBar(
                        segmentProgress: task.segmentProgress,
                        tint: task.status.accentColor
                    )
                    .frame(height: 6)
                } else if task.status == .completed {
                    // Solid completed bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.opacity(0.7))
                            .frame(width: geo.size.width, height: 6)
                    }
                    .frame(height: 6)
                }

                // Footer row: size + speed + ETA + actions
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SpeedLabel(bytesPerSecond: task.bytesPerSecond, status: task.status)
                        if task.status == .downloading || task.status == .paused {
                            Text("\(task.formattedDownloaded) / \(task.formattedSize)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if task.status == .completed {
                            Text(task.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let eta = task.eta {
                        Spacer()
                        Label(etaString(eta), systemImage: "clock")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    actionButtons
                }
            }
            .padding(16)
        }
        .transition(Theme.cardTransition)
    }

    // MARK: Destination label

    private var destinationLabel: String {
        if task.destinationPath.isEmpty { return "Downloads" }
        return URL(fileURLWithPath: task.destinationPath).lastPathComponent
    }

    // MARK: Action pill buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch task.status {
            case .downloading:
                PillButton(icon: "pause.fill",    color: .orange, action: onPause)
                PillButton(icon: "xmark",         color: .red,    action: onCancel)
            case .paused:
                PillButton(icon: "play.fill",     color: .blue,   action: onResume)
                PillButton(icon: "xmark",         color: .red,    action: onCancel)
            case .failed:
                PillButton(icon: "arrow.clockwise", color: .orange, action: onRetry)
                PillButton(icon: "xmark",           color: .red,    action: onCancel)
            case .waiting:
                PillButton(icon: "xmark",         color: .red,    action: onCancel)
            case .completed:
                PillButton(icon: "folder",        color: .green,  action: onReveal)
            }
        }
    }

    private static let etaFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    private func etaString(_ seconds: TimeInterval) -> String {
        Self.etaFormatter.string(from: seconds) ?? "—"
    }
}

// MARK: - ChunkProgressBar (IDM-style segment visualization)

struct ChunkProgressBar: View {
    /// One value per segment, each in [0, 1].
    let segmentProgress: [Double]
    let tint: Color

    /// Colors assigned per-segment — mirrors IDM's multi-colour segments.
    private let segmentColors: [Color] = [.blue, .cyan, .teal, .mint]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))

                // Segments — each occupies 1/N of the total bar width
                HStack(spacing: 1) {
                    ForEach(segmentProgress.indices, id: \.self) { i in
                        let segWidth = (geo.size.width - CGFloat(segmentProgress.count - 1)) / CGFloat(segmentProgress.count)
                        ZStack(alignment: .leading) {
                            // Empty segment track
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: segWidth)
                            // Filled portion
                            RoundedRectangle(cornerRadius: 2)
                                .fill(segmentColors[i % segmentColors.count].opacity(0.85))
                                .frame(width: max(0, segWidth * CGFloat(segmentProgress[i])))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - PillButton

struct PillButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DownloadTask helper

private extension DownloadTask {
    var formattedDownloaded: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }
}
