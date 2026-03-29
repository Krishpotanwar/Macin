// LocalHTTPServer.swift — Minimal HTTP server on 127.0.0.1:54322
// Receives download requests forwarded by the NativeMessagingHost.
//
// Endpoints:
//   POST /add    { "url": "https://..." }  → triggers addDownload callback
//   GET  /status                           → returns current downloads as JSON (for extension polling)
//
// Uses Network.NWListener (no third-party deps, no App Sandbox issues on loopback).

import Foundation
import Network

@MainActor
final class LocalHTTPServer {

    static let port: NWEndpoint.Port = 54322

    /// Called on the main actor whenever a valid download URL arrives.
    /// Parameters: (url, destination) — destination is "" when not specified.
    var onAddDownload: ((String, String) -> Void)?
    /// Called when the extension requests a JSON status snapshot.
    var onStatusRequest: (() -> String)?

    private var listener: NWListener?

    // MARK: - Lifecycle

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let l = try? NWListener(using: params, on: Self.port) else {
            print("[LocalHTTPServer] Failed to bind on port \(Self.port)")
            return
        }

        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        l.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                print("[LocalHTTPServer] listener error: \(err)")
            }
        }
        l.start(queue: .global(qos: .utility))
        listener = l
        print("[LocalHTTPServer] Listening on 127.0.0.1:\(Self.port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let data, !data.isEmpty,
                  let rawRequest = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let (status, body) = self.handle(rawRequest)
                self.respond(conn: conn, status: status, body: body)
            }
        }
    }

    private func handle(_ raw: String) -> (Int, String) {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return (400, #"{"error":"empty request"}"#) }

        // Route on method + path
        if requestLine.hasPrefix("POST /add") {
            return handleAdd(raw)
        } else if requestLine.hasPrefix("GET /status") {
            let json = onStatusRequest?() ?? "[]"
            return (200, json)
        } else if requestLine.hasPrefix("OPTIONS") {
            // Preflight (in case extension uses fetch)
            return (204, "")
        }
        return (404, #"{"error":"not found"}"#)
    }

    /// Parse { "url": "...", "destination": "..." } from the POST body and trigger the add callback.
    private func handleAdd(_ raw: String) -> (Int, String) {
        guard let bodyRange = raw.range(of: "\r\n\r\n"),
              let data = String(raw[bodyRange.upperBound...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let url = json["url"],
              let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host != nil
        else {
            return (400, #"{"error":"invalid or missing url"}"#)
        }

        let destination = json["destination"] ?? ""
        onAddDownload?(url, destination)
        return (200, #"{"status":"ok"}"#)
    }

    // MARK: - HTTP response helper

    private func respond(conn: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK"
                       : status == 204 ? "No Content"
                       : status == 400 ? "Bad Request"
                       : "Not Found"
        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(bodyData.count)",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var responseData = headers.data(using: .utf8)!
        responseData.append(bodyData)

        conn.send(content: responseData, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
