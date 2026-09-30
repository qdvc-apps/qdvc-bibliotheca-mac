import SwiftUI
import BibliothecaCore

/// Pane 1: the library filters, as a native source list with count badges.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section("Library") {
                row(.all)
            }
            Section("By Type") {
                ForEach(Builtin.typeOrder, id: \.self) { label in
                    row(.type(label))
                }
            }
            Section("Full Text") {
                row(.fulltext(.pdf))
                row(.fulltext(.epub))
                row(.fulltext(.missing))
            }
            Section("DOI") {
                row(.doi(hasDOI: true))
                row(.doi(hasDOI: false))
            }
            Section {
                if model.works.isEmpty {
                    Text("No works yet").foregroundStyle(.secondary)
                } else {
                    ForEach(model.works) { work in
                        row(.work(work.key))
                            .contextMenu {
                                Button("Reveal in Finder") { model.revealWork(work.key) }
                                Button("Open in Text Editor") { model.openWorkInTextEditor(work.key) }
                                Divider()
                                Button("New Work\u{2026}") { model.beginNewWork() }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("My Works")
                    Spacer()
                    Button {
                        model.beginNewWork()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Work (\u{2318}N)")
                }
            }
            if !model.starredAuthors.isEmpty {
                Section("Starred Authors") {
                    ForEach(model.starredAuthors) { author in
                        row(.author(author.authorID))
                            .contextMenu {
                                Button("Unstar") { model.setAuthorStarred(author.authorID, false) }
                            }
                    }
                }
            }
            if !model.starredOutlets.isEmpty {
                Section("Starred Outlets") {
                    ForEach(model.starredOutlets) { outlet in
                        row(.outlet(outlet.outletID))
                            .help(outlet.name)
                            .contextMenu {
                                Button("Show in Outlets") { model.revealOutlet(outlet.outletID) }
                                Button("Unstar") { model.setOutletStarred(outlet.outletID, false) }
                            }
                    }
                }
            }
            if let item = model.transientSidebarItem {
                Section("Query Results") {
                    row(item).italic()
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.sidebarSelection) { model.refreshRows() }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(model.title(for: item), systemImage: model.icon(for: item))
            .lineLimit(1)
            .badge(model.sidebarCounts[item] ?? 0)
            .tag(item)
    }
}
