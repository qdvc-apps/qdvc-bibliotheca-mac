import SwiftUI
import BibliothecaCore

/// The Outlets tab: journals and proceedings derived from the BibTeX, with
/// starring, nicknames and J-Flags.
struct OutletsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Table(model.outletRows, selection: $model.selectedOutletID, sortOrder: $model.outletSortOrder) {
                TableColumn("\u{2605}", value: \.starRank) { row in
                    StarButton(starred: row.starred) {
                        model.setOutletStarred(row.id, !row.starred)
                    }
                }
                .width(28)

                TableColumn("Outlet", value: \.name) { row in
                    Text(row.name).help(row.name)
                }
                .width(min: 200, ideal: 420)

                TableColumn("Nickname", value: \.nickname) { row in
                    Text(row.nickname).bold()
                }
                .width(min: 70, ideal: 100)

                TableColumn("J-Flags", value: \.jflags) { row in
                    Text(row.jflags)
                }
                .width(min: 70, ideal: 140)

                TableColumn("Records", value: \.count) { row in
                    Text(String(row.count)).monospacedDigit()
                }
                .width(min: 55, ideal: 65, max: 90)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = model.outletRows.first(where: { $0.id == id }) {
                    Button("Show Records in Catalogue") { model.showOutletWorks(id) }
                    Button(row.starred ? "Unstar" : "Star") { model.setOutletStarred(id, !row.starred) }
                    Divider()
                    Button("Set Nickname\u{2026}") { model.beginSetNickname(id) }
                    Button("Set J-Flags\u{2026}") { model.beginSetJflags(id) }
                }
            } primaryAction: { ids in
                model.showOutletWorks(ids.first)
            }
            .overlay {
                if model.outletRows.isEmpty {
                    if !model.outletSearchText.trimmed.isEmpty {
                        ContentUnavailableView.search(text: model.outletSearchText)
                    } else {
                        ContentUnavailableView("No Outlets", systemImage: "building.columns",
                                               description: Text(model.outletsStarredOnly
                                                                 ? "No outlet is starred yet."
                                                                 : "Journals and proceedings appear here as articles and papers are added."))
                    }
                }
            }

            Divider()
            HStack {
                Toggle("Starred Only", isOn: $model.outletsStarredOnly)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Set Nickname\u{2026}") { model.beginSetNickname(model.selectedOutletID) }
                    .disabled(model.selectedOutletID == nil)
                Button("Set J-Flags\u{2026}") { model.beginSetJflags(model.selectedOutletID) }
                    .disabled(model.selectedOutletID == nil)
                Button("Show Records in Catalogue") { model.showOutletWorks(model.selectedOutletID) }
                    .disabled(model.selectedOutletID == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .searchable(text: $model.outletSearchText, placement: .toolbar, prompt: "Filter outlets")
        .onChange(of: model.outletSearchText) { model.refreshOutletRows() }
        .onChange(of: model.outletsStarredOnly) { model.refreshOutletRows() }
        .onChange(of: model.outletSortOrder) { model.refreshOutletRows() }
    }
}
