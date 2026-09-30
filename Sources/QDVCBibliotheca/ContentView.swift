import AppKit
import Combine
import QuickLook
import SwiftUI

/// The main window. Like Activity Monitor, a segmented control centred in the
/// toolbar switches between the Catalogue, Authors, Outlets and DOI Lookup
/// tabs. Every tab shares one three-column split view (sidebar | list |
/// detail), so the sidebar, the toolbar and the tab control never move; only
/// the panes' contents change. The welcome screen shows when no workspace is
/// open.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.workspace == nil && !model.isLoading {
                WelcomeView()
            } else {
                MainSplitView()
                .dropDestination(for: URL.self) { urls, _ in
                    model.beginImport(files: urls)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $model.currentTab) {
                            ForEach(AppTab.allCases) { tab in
                                Text(tab.title).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Switch between the Catalogue, Authors, Outlets and DOI Lookup (\u{2318}1\u{2013}\u{2318}4)")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.beginImport()
                        } label: {
                            Label("Import BibTeX", systemImage: "square.and.arrow.down")
                        }
                        .help("Import BibTeX (\u{2318}I)")
                        .disabled(model.isLoading)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Reload changed files from disk (\u{2318}R)")
                        .disabled(model.isLoading)
                    }
                }
            }
        }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.statusLine)
        .overlay {
            if model.isLoading {
                ProgressView("Loading workspace\u{2026}")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .quickLookPreview($model.quickLookURL)
        .sheet(item: $model.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(model)
        }
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil },
                                    set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.flushNotes()
        }
    }
}

/// The one split view behind every tab. Keeping a single instance (rather than
/// one per tab) is what keeps the sidebar width, the toolbar layout and the
/// centred tab control stable when switching tabs, as the HIG expects of a
/// sidebar: a persistent list of the app's areas, hidden only by the user.
struct MainSplitView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Group {
                switch model.currentTab {
                case .catalogue: SidebarView()
                case .authors: AuthorsSidebar()
                case .outlets: OutletsSidebar()
                case .doiLookup: DOIHistorySidebar()
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            Group {
                switch model.currentTab {
                case .catalogue: CatalogueTableView()
                case .authors: AuthorsView()
                case .outlets: OutletsView()
                case .doiLookup: DOILookupView()
                }
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 700)
        } detail: {
            switch model.currentTab {
            case .catalogue: DetailView()
            case .authors: AuthorDetailView()
            case .outlets: OutletDetailView()
            case .doiLookup: DOIResultView()
            }
        }
        // One search field for all tabs (so the toolbar never changes shape);
        // it filters whatever the current tab lists.
        .searchable(text: searchText, placement: .toolbar, prompt: Text(searchPrompt))
    }

    private var searchText: Binding<String> {
        Binding(
            get: {
                switch model.currentTab {
                case .catalogue: return model.searchText
                case .authors: return model.authorSearchText
                case .outlets: return model.outletSearchText
                case .doiLookup: return model.doiHistorySearchText
                }
            },
            set: { text in
                switch model.currentTab {
                case .catalogue: model.searchText = text
                case .authors: model.authorSearchText = text
                case .outlets: model.outletSearchText = text
                case .doiLookup: model.doiHistorySearchText = text
                }
            })
    }

    private var searchPrompt: String {
        switch model.currentTab {
        case .catalogue: return "Filter records"
        case .authors: return "Filter authors"
        case .outlets: return "Filter outlets"
        case .doiLookup: return "Filter recent lookups"
        }
    }
}

/// Picks the view for the sheet that is open.
private struct SheetContent: View {
    @Environment(AppModel.self) private var model
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .importBibTeX(let request):
            ImportSheet(request: request)
        case .allocate(let ids):
            AllocateSheet(recordIDs: ids)
        case .newWork(let ids):
            NewWorkSheet(allocating: ids)
        case .rename(let id):
            RenameSheet(recordID: id)
        case .nickname(let id):
            NicknameSheet(outletID: id,
                          outletName: model.workspace?.outlets[id]?.name ?? id,
                          initialNickname: model.workspace?.outlets[id]?.nickname ?? "")
        case .jflags(let id):
            JFlagsSheet(outletID: id,
                        outletName: model.workspace?.outlets[id]?.name ?? id,
                        current: model.workspace?.outlets[id]?.sortedJflags() ?? [],
                        presets: Prefs.jflagPresets.map { $0.flag.trimmed }.filter { !$0.isEmpty })
        }
    }
}

/// Shown when no workspace is open.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("QDVC Bibliotheca")
                .font(.largeTitle.weight(.semibold))
            Text("Open a workspace folder \u{2014} the one containing bibtex and markdown \u{2014} to browse your library.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if !model.recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(Array(model.recentWorkspaces.prefix(5)), id: \.self) { path in
                        Button((path as NSString).abbreviatingWithTildeInPath) {
                            model.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
