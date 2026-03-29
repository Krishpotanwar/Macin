// ContentView.swift — Root view: blur + category tabs + adaptive grid + toolbar
import SwiftUI

struct ContentView: View {
    @State var viewModel: DownloadViewModel
    @State private var selectedCategory: DownloadFilter = .all

    init(viewModel: DownloadViewModel = DownloadViewModel(), xpcClient: EngineXPCClient? = nil) {
        // If a pre-built viewModel is passed (from MacinApp), use it directly.
        // Otherwise construct a new one (used in previews / standalone).
        _viewModel = State(initialValue: viewModel)
        _ = xpcClient // kept for future XPC wiring
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WindowAccessor()
                    .frame(width: 0, height: 0)
                VisualEffectBlur()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    toolbar
                    Divider().opacity(0.2)
                    filterTabs
                    Divider().opacity(0.12)
                    downloadList(geometry: geometry)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $viewModel.isAddSheetPresented) {
            AddURLSheet(isPresented: $viewModel.isAddSheetPresented) { url in
                viewModel.addDownload(url: url)
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Macin")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            Spacer()

            // Open Downloads folder
            Button {
                viewModel.openFolder(NSHomeDirectory() + "/Downloads")
            } label: {
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Downloads Folder")

            // Pause All
            if viewModel.hasActiveDownloads {
                Button {
                    viewModel.pauseAll()
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Pause All")
            }

            // Resume All
            if viewModel.hasPausedDownloads {
                Button {
                    viewModel.resumeAll()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Resume All")
            }

            // Add download
            Button {
                viewModel.isAddSheetPresented = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("Add URL")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Category filter tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DownloadFilter.allCases, id: \.self) { filter in
                    FilterTab(
                        filter: filter,
                        isSelected: selectedCategory == filter,
                        count: viewModel.count(for: filter)
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: Download list / empty state

    @ViewBuilder
    private func downloadList(geometry: GeometryProxy) -> some View {
        let visible = viewModel.filtered(by: selectedCategory)

        if visible.isEmpty {
            emptyState
        } else {
            let columns = geometry.size.width >= Theme.gridMinWidth
                ? [
                    GridItem(.flexible(), spacing: Theme.gridSpacing),
                    GridItem(.flexible(), spacing: Theme.gridSpacing)
                  ]
                : [GridItem(.flexible())]

            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.gridSpacing) {
                    ForEach(visible) { task in
                        DownloadCard(
                            task: task,
                            onPause:  { viewModel.pause(id: task.id) },
                            onResume: { viewModel.resume(id: task.id) },
                            onCancel: { viewModel.cancel(id: task.id) },
                            onRetry:  { viewModel.retry(id: task.id) },
                            onReveal: { viewModel.revealInFinder(task: task) }
                        )
                    }
                }
                .padding(16)
                .animation(Theme.springAnimation, value: visible.map(\.id))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedCategory == .all ? "arrow.down.circle" : selectedCategory.sfSymbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(selectedCategory == .all ? "No downloads yet" : "No \(selectedCategory.label) downloads")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + to add a URL")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DownloadFilter

enum DownloadFilter: String, CaseIterable {
    case all        = "All"
    case active     = "Active"
    case completed  = "Completed"
    case document   = "Documents"
    case video      = "Video"
    case audio      = "Audio"

    var label: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .all:       return "tray.full"
        case .active:    return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .document:  return "doc.fill"
        case .video:     return "film"
        case .audio:     return "music.note"
        }
    }
}

// MARK: - FilterTab

struct FilterTab: View {
    let filter: DownloadFilter
    let isSelected: Bool
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: filter.sfSymbol)
                    .font(.caption.weight(.medium))
                Text(filter.label)
                    .font(.caption.weight(.medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? Color.white.opacity(0.18)
                    : Color.clear
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DownloadViewModel filter extensions

extension DownloadViewModel {
    var hasActiveDownloads: Bool {
        downloads.contains { $0.status == .downloading }
    }

    var hasPausedDownloads: Bool {
        downloads.contains { $0.status == .paused }
    }

    func filtered(by filter: DownloadFilter) -> [DownloadTask] {
        switch filter {
        case .all:       return downloads
        case .active:    return downloads.filter { $0.status == .downloading || $0.status == .waiting }
        case .completed: return downloads.filter { $0.status == .completed }
        case .document:  return downloads.filter { $0.category == .document }
        case .video:     return downloads.filter { $0.category == .video }
        case .audio:     return downloads.filter { $0.category == .audio }
        }
    }

    func count(for filter: DownloadFilter) -> Int {
        filtered(by: filter).count
    }
}

#Preview {
    ContentView()
}
