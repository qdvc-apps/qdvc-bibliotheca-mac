import SwiftUI
import BibliothecaCore

/// Authors tab, sidebar: which authors to list.
struct AuthorsSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let counts = model.authorCounts
        List(selection: $model.authorFilter) {
            Section("Authors") {
                Label("All Authors", systemImage: "person.2")
                    .badge(counts.all)
                    .tag(AuthorFilter.all)
                Label("Starred", systemImage: "star")
                    .badge(counts.starred)
                    .tag(AuthorFilter.starred)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.authorFilter) { model.refreshAuthorRows() }
    }
}

/// Authors tab, list: every author derived from the BibTeX, with starring.
/// Starred authors become quick filters in the Catalogue sidebar.
struct AuthorsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.authorRows, selection: $model.selectedAuthorID, sortOrder: $model.authorSortOrder) {
            TableColumn("\u{2605}", value: \.starRank) { row in
                StarButton(starred: row.starred) {
                    model.setAuthorStarred(row.id, !row.starred)
                }
            }
            .width(28)

            TableColumn("Author", value: \.name) { row in
                Text(row.name).help(row.name)
            }
            .width(min: 140, ideal: 260)

            TableColumn("Author ID", value: \.id) { row in
                Text(row.id).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 200)

            TableColumn("Works", value: \.count) { row in
                Text(String(row.count)).monospacedDigit()
            }
            .width(min: 50, ideal: 60, max: 90)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let row = model.authorRows.first(where: { $0.id == id }) {
                Button("Show Works in Catalogue") { model.showAuthorWorks(id) }
                Button(row.starred ? "Unstar" : "Star") { model.setAuthorStarred(id, !row.starred) }
            }
        } primaryAction: { ids in
            model.showAuthorWorks(ids.first)
        }
        .overlay {
            if model.authorRows.isEmpty {
                if !model.authorSearchText.trimmed.isEmpty {
                    ContentUnavailableView.search(text: model.authorSearchText)
                } else {
                    ContentUnavailableView("No Authors", systemImage: "person.2",
                                           description: Text(model.authorFilter == .starred
                                                             ? "No author is starred yet."
                                                             : "Authors appear here as records are added."))
                }
            }
        }
        .onChange(of: model.authorSearchText) { model.refreshAuthorRows() }
        .onChange(of: model.authorSortOrder) { model.refreshAuthorRows() }
    }
}

/// Authors tab, detail: the selected author and their works.
struct AuthorDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selectedAuthorID, let author = model.workspace?.authors[id] {
            let starred = model.starredAuthors.contains { $0.authorID == id }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(author.displayName)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Text(id)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        model.setAuthorStarred(id, !starred)
                    } label: {
                        Label(starred ? "Starred" : "Star", systemImage: starred ? "star.fill" : "star")
                    }
                    .help(starred ? "Unstar (removes it from the Catalogue sidebar)"
                                  : "Star (adds it to the Catalogue sidebar)")
                }
                RecordList(title: "Works", ids: author.recordIDs)
                HStack {
                    Spacer()
                    Button("Show Works in Catalogue") { model.showAuthorWorks(id) }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("No Author Selected", systemImage: "person",
                                   description: Text("Select an author to see their works."))
        }
    }
}

/// Records listed in a detail pane; double-click shows one in the Catalogue.
struct RecordList: View {
    @Environment(AppModel.self) private var model
    let title: String
    let ids: [String]
    @State private var selection: String?

    var body: some View {
        let records = model.recordSummaries(ids)
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (\(records.count))")
                .font(.headline)
            List(records, selection: $selection) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.id)
                        .fontWeight(.medium)
                    Text([record.year, record.title].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first {
                    Button("Show in Catalogue") { model.revealRecord(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { model.revealRecord(id) }
            }
        }
    }
}

/// A clickable star for the ★ columns.
struct StarButton: View {
    let starred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .foregroundStyle(starred ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(starred ? "Unstar" : "Star")
    }
}
