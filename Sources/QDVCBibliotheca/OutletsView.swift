import SwiftUI
import BibliothecaCore

/// Outlets tab, sidebar: which outlets to list, including one filter per
/// J-Flag in use.
struct OutletsSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.outletFilter) {
            Section("Outlets") {
                row("All Outlets", "building.columns", .all)
                row("Starred", "star", .starred)
                row("With Nickname", "tag", .nicknamed)
                row("Without Nickname", "tag.slash", .notNicknamed)
            }
            Section("J-Flags") {
                ForEach(model.jflagsInUse()) { jflag in
                    row(jflag.flag, "flag", .jflag(jflag.flag))
                }
                row("No J-Flags", "flag.slash", .noJflags)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.outletFilter) { model.refreshOutletRows() }
    }

    private func row(_ title: String, _ icon: String, _ filter: OutletFilter) -> some View {
        Label(title, systemImage: icon)
            .lineLimit(1)
            .badge(model.outletCount(filter))
            .tag(filter)
    }
}

/// Outlets tab, list: journals and proceedings derived from the BibTeX.
struct OutletsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
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
            .width(min: 180, ideal: 320)

            TableColumn("Nickname", value: \.nickname) { row in
                Text(row.nickname).bold()
            }
            .width(min: 70, ideal: 90)

            TableColumn("J-Flags", value: \.jflags) { row in
                Text(row.jflags)
            }
            .width(min: 60, ideal: 110)

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
                } else if model.outletFilter != .all {
                    ContentUnavailableView("No Matching Outlets", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("No outlet matches the filter chosen in the sidebar."))
                } else {
                    ContentUnavailableView("No Outlets", systemImage: "building.columns",
                                           description: Text("Journals and proceedings appear here as articles and papers are added."))
                }
            }
        }
        .onChange(of: model.outletSearchText) { model.refreshOutletRows() }
        .onChange(of: model.outletSortOrder) { model.refreshOutletRows() }
    }
}

/// Outlets tab, detail: the selected outlet, its nickname and J-Flags, and its
/// records.
struct OutletDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selectedOutletID, let outlet = model.workspace?.outlets[id] {
            // Read the observable row (falls back to the model object when the
            // row is filtered out) so edits made in sheets show immediately.
            let row = model.outletRows.first { $0.id == id }
            let nickname = row?.nickname ?? outlet.nickname
            let jflags = row?.jflags ?? outlet.sortedJflags().joined(separator: ", ")
            let starred = model.starredOutlets.contains { $0.outletID == id }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(outlet.name)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        model.setOutletStarred(id, !starred)
                    } label: {
                        Label(starred ? "Starred" : "Star", systemImage: starred ? "star.fill" : "star")
                    }
                    .help(starred ? "Unstar (removes it from the Catalogue sidebar)"
                                  : "Star (adds it to the Catalogue sidebar)")
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Nickname").foregroundStyle(.secondary)
                        Text(nickname.isEmpty ? "None" : nickname)
                            .fontWeight(nickname.isEmpty ? .regular : .bold)
                            .foregroundStyle(nickname.isEmpty ? Color.secondary : Color.primary)
                        Button("Set Nickname\u{2026}") { model.beginSetNickname(id) }
                    }
                    GridRow {
                        Text("J-Flags").foregroundStyle(.secondary)
                        Text(jflags.isEmpty ? "None" : jflags)
                            .foregroundStyle(jflags.isEmpty ? Color.secondary : Color.primary)
                        Button("Set J-Flags\u{2026}") { model.beginSetJflags(id) }
                    }
                }
                RecordList(title: "Records", ids: outlet.recordIDs)
                HStack {
                    Spacer()
                    Button("Show Records in Catalogue") { model.showOutletWorks(id) }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("No Outlet Selected", systemImage: "building.columns",
                                   description: Text("Select an outlet to see its details and records."))
        }
    }
}
