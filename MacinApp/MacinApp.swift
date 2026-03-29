// MacinApp.swift — App entry point
import SwiftUI

@main
struct MacinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// XPC client — nil until Phase 3 XPC service target is bundled.
    /// When nil, DownloadViewModel runs in mock-simulation mode.
    @State private var xpcClient: EngineXPCClient? = nil
    @State private var viewModel = DownloadViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, xpcClient: xpcClient)
                .onAppear {
                    // Wire HTTP server → ViewModel so downloads from the browser extension
                    // are added directly to the active ViewModel.
                    appDelegate.httpServer.onAddDownload = { [weak viewModel] url, destination in
                        guard let vm = viewModel else { return }
                        vm.addDownload(url: url, destination: destination)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    appDelegate.httpServer.onStatusRequest = { [weak viewModel] in
                        viewModel?.statusJSON() ?? "[]"
                    }

                    // Uncomment when DownloadEngineXPC target is added:
                    // let client = EngineXPCClient()
                    // client.connect()
                    // client.startListening()
                    // xpcClient = client
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 500)
        .windowToolbarStyle(.unifiedCompact)
    }
}
