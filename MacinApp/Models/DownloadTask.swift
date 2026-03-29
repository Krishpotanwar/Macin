// DownloadTask.swift — Model + mock factory
import Foundation

struct DownloadTask: Identifiable, Codable, Sendable {
    let id: UUID
    var url: String
    var filename: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var bytesPerSecond: Double   // rolling average
    var status: DownloadStatus
    var addedAt: Date
    /// Per-segment downloaded bytes (up to 4). Empty when not using parallel segments.
    var segmentBytes: [Int64]
    /// Resolved destination directory, e.g. ~/Documents for PDFs. Empty until download starts.
    var destinationPath: String

    // MARK: Computed properties

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    var eta: TimeInterval? {
        guard bytesPerSecond > 0, status == .downloading else { return nil }
        return Double(totalBytes - downloadedBytes) / bytesPerSecond
    }

    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Fraction each segment has completed relative to its equal share of the total.
    /// Returns 4 values in [0, 1]. Falls back to even distribution when no segment data.
    var segmentProgress: [Double] {
        guard !segmentBytes.isEmpty, totalBytes > 0 else {
            let p = progress / 4.0
            return [p, p, p, p]
        }
        let share = Double(totalBytes) / Double(segmentBytes.count)
        return segmentBytes.map { min(Double($0) / share, 1.0) }
    }

    /// File category derived from extension — used for filter tabs.
    var category: FileCategory {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf":
            return .document
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm":
            return .video
        case "mp3", "aac", "flac", "wav", "ogg", "m4a", "aiff":
            return .audio
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic":
            return .image
        default:
            return .other
        }
    }

    // MARK: Mock data

    static func mockSet() -> [DownloadTask] {
        [
            DownloadTask(
                id: UUID(),
                url: "https://example.com/wwdc-session.mp4",
                filename: "WWDC_Session.mp4",
                totalBytes: 8_500_000_000,
                downloadedBytes: 3_200_000_000,
                bytesPerSecond: 12_500_000,
                status: .downloading,
                addedAt: .now,
                segmentBytes: [800_000_000, 820_000_000, 790_000_000, 790_000_000],
                destinationPath: "\(NSHomeDirectory())/Movies"
            ),
            DownloadTask(
                id: UUID(),
                url: "https://example.com/report.pdf",
                filename: "Annual_Report.pdf",
                totalBytes: 14_000_000,
                downloadedBytes: 7_000_000,
                bytesPerSecond: 0,
                status: .paused,
                addedAt: .now.addingTimeInterval(-600),
                segmentBytes: [1_750_000, 1_750_000, 1_750_000, 1_750_000],
                destinationPath: "\(NSHomeDirectory())/Documents"
            ),
            DownloadTask(
                id: UUID(),
                url: "https://example.com/xcode-docs.zip",
                filename: "XcodeDocs.zip",
                totalBytes: 450_000_000,
                downloadedBytes: 450_000_000,
                bytesPerSecond: 0,
                status: .completed,
                addedAt: .now.addingTimeInterval(-3600),
                segmentBytes: [],
                destinationPath: "\(NSHomeDirectory())/Downloads"
            ),
            DownloadTask(
                id: UUID(),
                url: "https://example.com/broken.zip",
                filename: "broken.zip",
                totalBytes: 100_000_000,
                downloadedBytes: 23_000_000,
                bytesPerSecond: 0,
                status: .failed,
                addedAt: .now.addingTimeInterval(-120),
                segmentBytes: [],
                destinationPath: "\(NSHomeDirectory())/Downloads"
            ),
        ]
    }
}

// MARK: - FileCategory

enum FileCategory: String, CaseIterable, Codable, Sendable {
    case document = "Documents"
    case video    = "Video"
    case audio    = "Audio"
    case image    = "Images"
    case other    = "Other"

    var sfSymbol: String {
        switch self {
        case .document: return "doc.fill"
        case .video:    return "film"
        case .audio:    return "music.note"
        case .image:    return "photo"
        case .other:    return "archivebox.fill"
        }
    }
}
