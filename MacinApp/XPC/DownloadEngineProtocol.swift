// DownloadEngineProtocol.swift — XPC interface definition
// All types must be NSSecureCoding-compatible (String, not UUID).
import Foundation

@objc protocol DownloadEngineProtocol {
    /// Add a download. Reply delivers the assigned task UUID, or empty string on failure.
    func addDownload(url: String, destinationPath: String, reply: @escaping (String) -> Void)

    /// Pause a download. Reply delivers true on success.
    func pauseDownload(id: String, reply: @escaping (Bool) -> Void)

    /// Resume a paused download. Reply delivers true on success.
    func resumeDownload(id: String, reply: @escaping (Bool) -> Void)

    /// Cancel and remove a download. Reply delivers true on success.
    func cancelDownload(id: String, reply: @escaping (Bool) -> Void)

    /// Returns a JSON array string of all task snapshots.
    func getStatus(reply: @escaping (String) -> Void)
}
