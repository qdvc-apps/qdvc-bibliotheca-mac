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
            Section("My Works") {
                if model.works.isEmpty {
                    Text("No works yet").foregroundStyle(.secondary)
                } else {
                    ForEach(model.works) { work in
                        row(.work(work.key))
                    }
                }
            }
            if !model.starredAuthors.isEmpty {
                Section("Starred Authors") {
                    ForEach(model.starredAuthors) { author in
                        row(.author(author.authorID))
                    }
                }
            }
            if !model.starredOutlets.isEmpty {
                Section("Starred Outlets") {
                    ForEach(model.starredOutlets) { outlet in
                        row(.outlet(outlet.outletID))
                            .help(outlet.name)
                    }
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
