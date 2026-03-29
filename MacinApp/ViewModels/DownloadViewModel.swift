// DownloadViewModel.swift — @MainActor @Observable class
// Drives UI from either the live XPC engine or mock simulation (when xpcClient is nil).
import Foundation
import AppKit

@MainActor @Observable
final class DownloadViewModel {
    var downloads: [DownloadTask] = []
    var isAddSheetPresented = false

    /// Injected at launch when XPC service is available; nil falls back to mock simulation.
    private let xpcClient: EngineXPCClient?

    nonisolated(unsafe) private var simulationTask: Task<Void, Never>?

    // MARK: Init

    init(xpcClient: EngineXPCClient? = nil) {
        self.xpcClient = xpcClient
        if let client = xpcClient {
            // Live mode: seed with empty array, populate from engine status + WebSocket
            client.onProgress = { [weak self] event in
                self?.applyProgress(event)
            }
            Task { await self.refreshFromEngine() }
        } else {
            // Mock mode: start empty, simulation activates when downloads are added
            downloads = []
            startSimulation()
        }
    }

    deinit {
        simulationTask?.cancel()
    }

    // MARK: Public API

    func addDownload(url: String, destination: String = "") {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host != nil else { return }

        let rawName = parsed.lastPathComponent
        let filename = rawName.isEmpty ? "download" : rawName

        let resolvedDest = destination.isEmpty
            ? (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? (NSHomeDirectory() + "/Downloads"))
            : destination

        if let client = xpcClient {
            Task {
                let assignedID = await client.addDownload(url: trimmed, destinationPath: resolvedDest)
                guard !assignedID.isEmpty else { return }
                let task = DownloadTask(
                    id: UUID(uuidString: assignedID) ?? UUID(),
                    url: trimmed,
                    filename: filename,
                    totalBytes: 0,
                    downloadedBytes: 0,
                    bytesPerSecond: 0,
                    status: .waiting,
                    addedAt: .now,
                    segmentBytes: [],
                    destinationPath: resolvedDest
                )
                downloads.append(task)
            }
        } else {
            downloads.append(DownloadTask(
                id: UUID(),
                url: trimmed,
                filename: filename,
                totalBytes: 500_000_000,
                downloadedBytes: 0,
                bytesPerSecond: 0,
                status: .waiting,
                addedAt: .now,
                segmentBytes: [],
                destinationPath: resolvedDest
            ))
        }
    }

    func pause(id: UUID) {
        if let client = xpcClient {
            Task { _ = await client.pause(id: id.uuidString) }
        }
        mutate(id: id) { $0.status = .paused; $0.bytesPerSecond = 0 }
    }

    func resume(id: UUID) {
        if let client = xpcClient {
            Task { _ = await client.resume(id: id.uuidString) }
        }
        mutate(id: id) { $0.status = .downloading }
    }

    func cancel(id: UUID) {
        if let client = xpcClient {
            Task { _ = await client.cancel(id: id.uuidString) }
        }
        downloads.removeAll { $0.id == id }
    }

    func retry(id: UUID) {
        mutate(id: id) { $0.status = .waiting; $0.downloadedBytes = 0; $0.bytesPerSecond = 0 }
    }

    // MARK: XPC / WebSocket live updates

    private func applyProgress(_ event: ProgressEvent) {
        guard let id = UUID(uuidString: event.id) else { return }
        let newStatus = DownloadStatus(rawValue: event.status) ?? .downloading
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].downloadedBytes = Int64(event.downloadedBytes)
            downloads[idx].totalBytes      = Int64(event.totalBytes)
            downloads[idx].bytesPerSecond  = event.bytesPerSecond
            downloads[idx].status          = newStatus
            downloads[idx].segmentBytes    = event.segmentBytes.map { Int64($0) }
            if !event.destination.isEmpty {
                downloads[idx].destinationPath = event.destination
            }
        }
    }

    // MARK: Bulk controls

    func pauseAll() {
        for task in downloads where task.status == .downloading {
            pause(id: task.id)
        }
    }

    func resumeAll() {
        for task in downloads where task.status == .paused {
            resume(id: task.id)
        }
    }

    /// Open the given folder (or ~/Downloads as fallback) in Finder.
    func openFolder(_ path: String) {
        let url = URL(fileURLWithPath: path.isEmpty ? (NSHomeDirectory() + "/Downloads") : path)
        NSWorkspace.shared.open(url)
    }

    /// Reveal a completed download file in Finder.
    func revealInFinder(task: DownloadTask) {
        let dir = task.destinationPath.isEmpty ? NSHomeDirectory() + "/Downloads" : task.destinationPath
        let fileURL = URL(fileURLWithPath: dir).appendingPathComponent(task.filename)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func refreshFromEngine() async {
        guard let client = xpcClient else { return }
        let json = await client.getStatus()
        guard let data = json.data(using: .utf8),
              let snapshots = try? JSONDecoder().decode([EngineSnapshot].self, from: data) else { return }
        for snap in snapshots {
            guard let id = UUID(uuidString: snap.id) else { continue }
            let status = DownloadStatus(rawValue: snap.status) ?? .waiting
            if let idx = downloads.firstIndex(where: { $0.id == id }) {
                downloads[idx].downloadedBytes = Int64(snap.downloadedBytes)
                downloads[idx].totalBytes = Int64(snap.totalBytes)
                downloads[idx].bytesPerSecond = snap.bytesPerSecond
                downloads[idx].status = status
            } else {
                downloads.append(DownloadTask(
                    id: id,
                    url: snap.url,
                    filename: snap.filename,
                    totalBytes: Int64(snap.totalBytes),
                    downloadedBytes: Int64(snap.downloadedBytes),
                    bytesPerSecond: snap.bytesPerSecond,
                    status: status,
                    addedAt: .now,
                    segmentBytes: [],
                    destinationPath: snap.destination
                ))
            }
        }
    }

    // MARK: Mock simulation

    private func startSimulation() {
        simulationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
    }

    private func tick() {
        for idx in downloads.indices {
            guard downloads[idx].status == .downloading else { continue }
            let increment = Int64.random(in: 8_000_000...15_000_000)
            var updated = downloads[idx]
            updated.downloadedBytes = min(updated.downloadedBytes + increment, updated.totalBytes)
            updated.bytesPerSecond = Double(increment)
            if updated.downloadedBytes >= updated.totalBytes {
                updated.status = .completed
                updated.bytesPerSecond = 0
            }
            downloads[idx] = updated
        }
        let activeCount = downloads.filter { $0.status == .downloading }.count
        let slots = max(0, 3 - activeCount)
        let waitingIndices = downloads.indices.filter { downloads[$0].status == .waiting }
        for idx in waitingIndices.prefix(slots) {
            var updated = downloads[idx]
            updated.status = .downloading
            downloads[idx] = updated
        }
    }

    // MARK: Status JSON (for browser extension polling)

    func statusJSON() -> String {
        let items = downloads.map { task -> String in
            let status = task.status.rawValue
            let name = task.filename
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let pct = task.totalBytes > 0
                ? Int((Double(task.downloadedBytes) / Double(task.totalBytes)) * 100)
                : 0
            return """
            {"id":"\(task.id.uuidString)","filename":"\(name)","status":"\(status)","percent":\(pct)}
            """
        }
        return "[\(items.joined(separator: ","))]"
    }

    // MARK: Helpers

    private func mutate(id: UUID, _ block: (inout DownloadTask) -> Void) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        var updated = downloads[idx]
        block(&updated)
        downloads[idx] = updated
    }
}

// MARK: - Engine snapshot (mirrors Rust TaskSnapshot)

private struct EngineSnapshot: Decodable {
    let id: String
    let url: String
    let filename: String
    let totalBytes: UInt64
    let downloadedBytes: UInt64
    let bytesPerSecond: Double
    let status: String
    let destination: String

    enum CodingKeys: String, CodingKey {
        case id, url, filename, status, destination
        case totalBytes      = "total_bytes"
        case downloadedBytes = "downloaded_bytes"
        case bytesPerSecond  = "bytes_per_second"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,  forKey: .id)
        url             = try c.decode(String.self,  forKey: .url)
        filename        = try c.decode(String.self,  forKey: .filename)
        totalBytes      = try c.decode(UInt64.self,  forKey: .totalBytes)
        downloadedBytes = try c.decode(UInt64.self,  forKey: .downloadedBytes)
        bytesPerSecond  = try c.decode(Double.self,  forKey: .bytesPerSecond)
        status          = try c.decode(String.self,  forKey: .status)
        destination     = (try? c.decode(String.self, forKey: .destination)) ?? ""
    }
}
