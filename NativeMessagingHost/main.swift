// NativeMessagingHost/main.swift
// Chrome/Firefox Native Messaging host.
// Protocol: each message is a 4-byte little-endian length prefix followed by a UTF-8 JSON body.
// This binary is launched by the browser, communicates via stdin/stdout, and forwards
// validated download URLs to the Macin app via a local HTTP endpoint (port 54322).
//
// Security rules enforced here (per megaprompt):
//   1. Only http/https URLs accepted — all others are silently dropped.
//   2. JSON schema validated before any action.
//   3. No eval / exec of incoming data.
//   4. All inter-process communication is localhost-only.

import Foundation

// MARK: - Message types

struct IncomingMessage: Decodable {
    let action: String      // "add_download" | "ping" | "open_folder"
    let url: String?        // only present for add_download
    let destination: String? // optional custom save directory
    let filename: String?   // optional suggested filename (from browser)
}

struct OutgoingMessage: Encodable {
    let status: String      // "ok" | "error" | "pong"
    let message: String?
}

// MARK: - I/O helpers (Native Messaging framing)

func readMessage() -> Data? {
    // Read 4-byte length prefix (little-endian UInt32)
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    let bytesRead = FileHandle.standardInput.readData(ofLength: 4)
    guard bytesRead.count == 4 else { return nil }
    lengthBytes = Array(bytesRead)
    let length = UInt32(lengthBytes[0])
                | UInt32(lengthBytes[1]) << 8
                | UInt32(lengthBytes[2]) << 16
                | UInt32(lengthBytes[3]) << 24
    guard length > 0, length < 1_000_000 else { return nil }   // sanity cap: 1 MB
    return FileHandle.standardInput.readData(ofLength: Int(length))
}

func sendMessage(_ msg: OutgoingMessage) {
    guard let data = try? JSONEncoder().encode(msg) else { return }
    var length = UInt32(data.count).littleEndian
    let lengthData = withUnsafeBytes(of: &length) { Data($0) }
    FileHandle.standardOutput.write(lengthData)
    FileHandle.standardOutput.write(data)
}

// MARK: - URL validation

func isValidDownloadURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString),
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          url.host != nil else { return false }
    return true
}

// MARK: - Forward to Macin app via local HTTP

func forwardToMacin(url: String, destination: String, filename: String) {
    guard let endpoint = URL(string: "http://127.0.0.1:54322/add") else { return }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: String] = ["url": url]
    if !destination.isEmpty { body["destination"] = destination }
    if !filename.isEmpty    { body["filename"] = filename }
    request.httpBody = try? JSONEncoder().encode(body)
    request.timeoutInterval = 5
    URLSession.shared.dataTask(with: request).resume()
}

// MARK: - Open folder in Finder

func openDownloadsFolder() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let downloadsURL = home.appendingPathComponent("Downloads")
    // Use `open` CLI — NSWorkspace is not available in a non-GUI process.
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = [downloadsURL.path]
    try? proc.run()
}

// MARK: - Main message loop

func runLoop() {
    while true {
        guard let data = readMessage() else {
            // stdin closed — browser extension disconnected. Exit cleanly.
            exit(0)
        }
        guard let msg = try? JSONDecoder().decode(IncomingMessage.self, from: data) else {
            sendMessage(OutgoingMessage(status: "error", message: "invalid JSON schema"))
            continue
        }

        switch msg.action {
        case "ping":
            sendMessage(OutgoingMessage(status: "pong", message: nil))

        case "add_download":
            guard let url = msg.url, isValidDownloadURL(url) else {
                sendMessage(OutgoingMessage(status: "error", message: "invalid or missing url"))
                continue
            }
            forwardToMacin(url: url, destination: msg.destination ?? "", filename: msg.filename ?? "")
            sendMessage(OutgoingMessage(status: "ok", message: "queued"))

        case "open_folder":
            openDownloadsFolder()
            sendMessage(OutgoingMessage(status: "ok", message: nil))

        default:
            sendMessage(OutgoingMessage(status: "error", message: "unknown action"))
        }
    }
}

// URLSession tasks are async — keep the process alive after starting the loop.
RunLoop.main.perform { runLoop() }
RunLoop.main.run()
