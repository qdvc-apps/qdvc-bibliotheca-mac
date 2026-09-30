import AppKit
import Combine
import QuickLook
import SwiftUI

/// The main window: a three-column split view (filters | records | detail),
/// or the welcome screen when no workspace is open.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.workspace == nil && !model.isLoading {
                WelcomeView()
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                } content: {
                    CatalogueTableView()
                        .navigationSplitViewColumnWidth(min: 420, ideal: 700)
                } detail: {
                    DetailView()
                }
                .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter")
                .onChange(of: model.searchText) { model.refreshRows() }
                .dropDestination(for: URL.self) { urls, _ in
                    model.beginImport(files: urls)
                }
                .toolbar {
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
        .sheet(item: $model.importRequest) { request in
            ImportSheet(request: request)
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
