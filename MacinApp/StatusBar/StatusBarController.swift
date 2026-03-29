// StatusBarController.swift — NSStatusItem + NSMenu for background-mode visibility
import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        setupMenu()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.down.circle",
                               accessibilityDescription: "Macin Download Manager")
        button.image?.isTemplate = true  // renders correctly in both light and dark menu bar
    }

    private func setupMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Macin", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Macin", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Bring the first window (ContentView) to front; create it if it was closed.
        if let window = NSApp.windows.first(where: { $0.isVisible || !$0.isMiniaturized }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Badge

    /// Update the icon to reflect active download state.
    /// Call from DownloadViewModel when the downloading count changes.
    func updateBadge(activeDownloads: Int) {
        guard let button = statusItem.button else { return }
        let symbolName = activeDownloads > 0 ? "arrow.down.circle.fill" : "arrow.down.circle"
        let description = activeDownloads > 0
            ? "Macin — \(activeDownloads) active download\(activeDownloads == 1 ? "" : "s")"
            : "Macin Download Manager"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.image?.isTemplate = true
    }
}
