import SwiftUI
import BibliothecaCore

/// DOI Lookup tab, sidebar: this session's lookups, newest first.
struct DOIHistorySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let items = model.filteredDOIHistory
        List(selection: $model.selectedHistoryDOI) {
            Section("Recent Lookups") {
                if items.isEmpty {
                    Text(model.doiHistory.isEmpty ? "No lookups yet" : "No matches")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.doi)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(item.foundID ?? "Not in library")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: item.foundID == nil ? "questionmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(item.foundID == nil ? Color.secondary : Color.green)
                    }
                    .help(item.doi)
                    .tag(item.doi)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.selectedHistoryDOI) { model.historySelectionChanged() }
    }
}

/// DOI Lookup tab, middle pane: the lookup form.
struct DOILookupView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Text("DOI Lookup")
                .font(.title2.weight(.semibold))
            Text("Check whether a DOI is already in your library. A bare DOI and a doi.org link both work.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("e.g. 10.1234/example", text: $model.doiQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($fieldFocused)
                    .onSubmit { model.lookupDOI() }
                Button("Look Up") { model.lookupDOI() }
                    .disabled(model.doiQuery.trimmed.isEmpty)
            }
            Text("Your lookups are listed in the sidebar for this session.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { fieldFocused = true }
    }
}

/// DOI Lookup tab, detail: the outcome of the current lookup.
struct DOIResultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.doiOutcome {
        case .found(let id)?:
            if let rec = model.workspace?.record(id) {
                FoundRecordView(record: rec)
            } else {
                ContentUnavailableView("Record Not Found", systemImage: "exclamationmark.triangle",
                                       description: Text("\(id) is no longer in the library."))
            }
        case .notFound(let doi)?:
            ContentUnavailableView {
                Label("Not in Your Library", systemImage: "questionmark.circle")
            } description: {
                Text("No record has the DOI \(doi).")
            } actions: {
                Button("Import BibTeX\u{2026}") { model.beginImport() }
            }
        case .empty?:
            ContentUnavailableView("Enter a DOI", systemImage: "magnifyingglass",
                                   description: Text("Type or paste a DOI, then press Return."))
        case nil:
            ContentUnavailableView("No Lookup Yet", systemImage: "link",
                                   description: Text("Look up a DOI to see whether it\u{2019}s already in your library."))
        }
    }
}

private struct FoundRecordView: View {
    @Environment(AppModel.self) private var model
    let record: Record

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("In your library", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text(record.bibliothecaID)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            GroupBox {
                Text(Markup.attributed(record.apaMarkup()))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            HStack {
                // No .defaultAction here: Return must stay with the DOI field.
                Button("Show in Catalogue") { model.revealRecord(record.bibliothecaID) }
                if model.hasFulltext(.pdf, id: record.bibliothecaID) {
                    Button("Open PDF") { model.openFulltext(.pdf, id: record.bibliothecaID) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
