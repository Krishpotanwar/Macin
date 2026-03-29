// EngineXPCClient.swift — NSXPCConnection wrapper + WebSocket listener for live progress
import Foundation
import Network

/// Bridges the SwiftUI layer to the XPC service.
/// All public methods are called on the MainActor; XPC callbacks are marshalled back via MainActor.run.
@MainActor
final class EngineXPCClient {

    // MARK: - XPC connection

    private var connection: NSXPCConnection?

    /// Connect to the XPC helper service. Call once at app launch.
    func connect() {
        let conn = NSXPCConnection(serviceName: "com.krishpotanwar.macin.DownloadEngineXPC")
        conn.remoteObjectInterface = NSXPCInterface(with: DownloadEngineProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connection = nil
            }
        }
        conn.resume()
        connection = conn
    }

    private var proxy: (any DownloadEngineProtocol)? {
        connection?.remoteObjectProxyWithErrorHandler { error in
            print("[XPC] error: \(error.localizedDescription)")
        } as? any DownloadEngineProtocol
    }

    // MARK: - Download operations

    func addDownload(url: String, destinationPath: String) async -> String {
        await withCheckedContinuation { cont in
            guard let p = proxy else { cont.resume(returning: ""); return }
            p.addDownload(url: url, destinationPath: destinationPath) { id in
                Task { @MainActor in cont.resume(returning: id) }
            }
        }
    }

    func pause(id: String) async -> Bool {
        await withCheckedContinuation { cont in
            guard let p = proxy else { cont.resume(returning: false); return }
            p.pauseDownload(id: id) { ok in
                Task { @MainActor in cont.resume(returning: ok) }
            }
        }
    }

    func resume(id: String) async -> Bool {
        await withCheckedContinuation { cont in
            guard let p = proxy else { cont.resume(returning: false); return }
            p.resumeDownload(id: id) { ok in
                Task { @MainActor in cont.resume(returning: ok) }
            }
        }
    }

    func cancel(id: String) async -> Bool {
        await withCheckedContinuation { cont in
            guard let p = proxy else { cont.resume(returning: false); return }
            p.cancelDownload(id: id) { ok in
                Task { @MainActor in cont.resume(returning: ok) }
            }
        }
    }

    func getStatus() async -> String {
        await withCheckedContinuation { cont in
            guard let p = proxy else { cont.resume(returning: "[]"); return }
            p.getStatus { json in
                Task { @MainActor in cont.resume(returning: json) }
            }
        }
    }

    // MARK: - WebSocket progress listener

    private var wsTask: URLSessionWebSocketTask?
    /// Called on MainActor with each progress event received from the engine.
    var onProgress: ((ProgressEvent) -> Void)?

    func startListening() {
        let url = URL(string: "ws://127.0.0.1:54321")!
        wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask?.resume()
        receiveNext()
    }

    func stopListening() {
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
    }

    private func receiveNext() {
        wsTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(.string(let text)):
                    if let data = text.data(using: .utf8),
                       let event = try? JSONDecoder().decode(ProgressEvent.self, from: data) {
                        self.onProgress?(event)
                    }
                    self.receiveNext()
                case .success:
                    self.receiveNext()
                case .failure:
                    // Retry after 2s if disconnected
                    try? await Task.sleep(for: .seconds(2))
                    self.startListening()
                }
            }
        }
    }
}

// MARK: - WebSocket event model

/// Mirrors the Rust `ProgressEvent` struct (JSON-decoded from WebSocket).
struct ProgressEvent: Decodable {
    let id: String
    let downloadedBytes: UInt64
    let totalBytes: UInt64
    let bytesPerSecond: Double
    let status: String
    /// Per-segment downloaded bytes. Empty for single-stream downloads.
    let segmentBytes: [UInt64]
    /// Estimated seconds remaining (0 when unknown).
    let etaSeconds: Double
    /// Resolved destination directory.
    let destination: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case downloadedBytes = "downloaded_bytes"
        case totalBytes      = "total_bytes"
        case bytesPerSecond  = "bytes_per_second"
        case segmentBytes    = "segment_bytes"
        case etaSeconds      = "eta_seconds"
        case destination
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,   forKey: .id)
        downloadedBytes = try c.decode(UInt64.self,   forKey: .downloadedBytes)
        totalBytes      = try c.decode(UInt64.self,   forKey: .totalBytes)
        bytesPerSecond  = try c.decode(Double.self,   forKey: .bytesPerSecond)
        status          = try c.decode(String.self,   forKey: .status)
        segmentBytes    = (try? c.decode([UInt64].self, forKey: .segmentBytes)) ?? []
        etaSeconds      = (try? c.decode(Double.self,   forKey: .etaSeconds))  ?? 0
        destination     = (try? c.decode(String.self,   forKey: .destination)) ?? ""
    }
}
