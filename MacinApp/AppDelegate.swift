// AppDelegate.swift — App lifecycle: SMAppService + StatusBar + LocalHTTPServer
import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?
    let httpServer = LocalHTTPServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBackgroundService()
        statusBarController = StatusBarController()
        httpServer.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        httpServer.stop()
    }

    /// Keep the app alive in the status bar when the last window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: SMAppService

    private func registerBackgroundService() {
        let service = SMAppService.mainApp
        do {
            if service.status == .notRegistered {
                try service.register()
            }
        } catch {
            print("[Macin] SMAppService registration failed: \(error.localizedDescription)")
        }
    }
}
