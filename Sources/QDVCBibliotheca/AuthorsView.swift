import SwiftUI
import BibliothecaCore

/// The Authors tab: every author derived from the BibTeX, with starring.
/// Starred authors become quick filters in the Catalogue sidebar.
struct AuthorsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
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
                .width(min: 160, ideal: 320)

                TableColumn("Author ID", value: \.id) { row in
                    Text(row.id).foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 240)

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
                                               description: Text(model.authorsStarredOnly
                                                                 ? "No author is starred yet."
                                                                 : "Authors appear here as records are added."))
                    }
                }
            }

            Divider()
            HStack {
                Toggle("Starred Only", isOn: $model.authorsStarredOnly)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Show Works in Catalogue") { model.showAuthorWorks(model.selectedAuthorID) }
                    .disabled(model.selectedAuthorID == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .searchable(text: $model.authorSearchText, placement: .toolbar, prompt: "Filter authors")
        .onChange(of: model.authorSearchText) { model.refreshAuthorRows() }
        .onChange(of: model.authorsStarredOnly) { model.refreshAuthorRows() }
        .onChange(of: model.authorSortOrder) { model.refreshAuthorRows() }
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
