import SwiftUI
import BibliothecaCore

/// A value snapshot of one record for the table (rebuilt on every change, so
/// SwiftUI can diff rows cheaply).
struct CatalogueRow: Identifiable, Hashable {
    let id: String
    let author: String
    let year: String
    let yearKey: YearKey
    let jflags: String
    let outletNickname: String
    let outletName: String
    let title: String
    let typeLabel: String
    let hasPDF: Bool
    let hasEPUB: Bool

    init(_ rec: Record, outlet: Outlet?, jflagPriority: [String: Double]) {
        id = rec.bibliothecaID
        author = rec.author
        year = rec.year
        yearKey = YearKey(rec.year)
        let flags = CatalogueSupport.orderJflags(outlet?.sortedJflags() ?? [], priority: jflagPriority)
        jflags = flags.isEmpty ? "\u{2014}" : flags.joined(separator: ", ")
        outletNickname = outlet?.nickname ?? ""
        outletName = outlet?.name ?? rec.outlet
        title = rec.title
        typeLabel = rec.typeLabel
        hasPDF = rec.hasPDF
        hasEPUB = rec.hasEPUB
    }

    /// PDF first, then EPUB, then nothing (for sorting the icon column).
    var fulltextRank: Int { (hasPDF ? 2 : 0) + (hasEPUB ? 1 : 0) }

    var outletSortKey: String { outletName.lowercased() }

    /// "(JBIB) Journal of Bibliotheca" with the nickname in bold.
    var outletDisplay: AttributedString {
        guard !outletNickname.isEmpty else { return AttributedString(outletName) }
        var nick = AttributedString("(\(outletNickname))")
        nick.inlinePresentationIntent = .stronglyEmphasized
        return nick + AttributedString(" \(outletName)")
    }

    /// Case-insensitive match against every visible text column.
    func matches(_ needle: String) -> Bool {
        [id, author, year, jflags, outletNickname, outletName, title, typeLabel]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

struct CatalogueTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.rows, selection: $model.selectedID, sortOrder: $model.sortOrder) {
            TableColumn("", value: \.fulltextRank) { row in
                FulltextIcon(hasPDF: row.hasPDF, hasEPUB: row.hasEPUB)
            }
            .width(18)

            TableColumn("Bibliotheca ID", value: \.id) { row in
                Text(row.id)
            }
            .width(min: 110, ideal: 170)

            TableColumn("Author", value: \.author) { row in
                Text(row.author).help(row.author)
            }
            .width(min: 100, ideal: 200)

            TableColumn("Year", value: \.yearKey) { row in
                Text(row.year).monospacedDigit()
            }
            .width(min: 40, ideal: 48, max: 70)

            TableColumn("J-Flags", value: \.jflags) { row in
                Text(row.jflags)
            }
            .width(min: 50, ideal: 80)

            TableColumn("Outlet", value: \.outletSortKey) { row in
                Text(row.outletDisplay).help(row.outletName)
            }
            .width(min: 100, ideal: 220)

            TableColumn("Title", value: \.title) { row in
                Text(row.title).help(row.title)
            }
            .width(min: 150, ideal: 360)

            TableColumn("Type", value: \.typeLabel) { row in
                Text(row.typeLabel)
            }
            .width(min: 70, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            RecordMenuItems(id: ids.first)
        } primaryAction: { ids in
            model.primaryAction(ids)
        }
        .onChange(of: model.sortOrder) { model.refreshRows() }
        .onChange(of: model.selectedID) { model.selectionChanged() }
        .overlay {
            if model.rows.isEmpty && !model.isLoading {
                if !model.searchText.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                } else if model.currentWorkKey != nil {
                    ContentUnavailableView("No Records in This Work", systemImage: "folder",
                                           description: Text("Right-click a record and choose Allocate to My Works\u{2026}, or import BibTeX while this work is selected."))
                } else {
                    ContentUnavailableView("No Records", systemImage: "tray",
                                           description: Text("Nothing in this part of the library."))
                }
            }
        }
    }
}

struct FulltextIcon: View {
    let hasPDF: Bool
    let hasEPUB: Bool

    var body: some View {
        if hasPDF {
            Image(systemName: "doc.richtext").foregroundStyle(.red).help("PDF available")
        } else if hasEPUB {
            Image(systemName: "book").foregroundStyle(.blue).help("EPUB available")
        } else {
            Color.clear
        }
    }
}

/// The record actions, shared by the table's context menu and the Record
/// menu in the menu bar (the successor to the GTK record right-click menu).
struct RecordMenuItems: View {
    @Environment(AppModel.self) private var model
    let id: String?

    var body: some View {
        let hasPDF = model.hasFulltext(.pdf, id: id)
        let hasEPUB = model.hasFulltext(.epub, id: id)

        Button("Open PDF") { model.openFulltext(.pdf, id: id) }
            .disabled(!hasPDF)
        Button("Open EPUB") { model.openFulltext(.epub, id: id) }
            .disabled(!hasEPUB)
        Button("Quick Look") { model.quickLook(id) }
            .disabled(!hasPDF && !hasEPUB)
        Divider()
        Button("Copy Bibliotheca ID") { model.copyID(id) }
            .disabled(id == nil)
        Divider()
        Button("Allocate to My Works\u{2026}") { model.beginAllocate(id.map { [$0] } ?? []) }
            .disabled(id == nil)
        Button("Rename Bibliotheca ID\u{2026}") { model.beginRename(id) }
            .disabled(id == nil)
        if let outletID = model.outletID(forRecord: id) {
            Button("Show Outlet") { model.revealOutlet(outletID) }
        }
        Divider()
        Button("Reveal .bib in Finder") { model.revealInFinder(id, markdown: false) }
            .disabled(id == nil)
        Button("Reveal .md in Finder") { model.revealInFinder(id, markdown: true) }
            .disabled(id == nil)
        Button("Open .bib in Text Editor") { model.openInTextEditor(id, markdown: false) }
            .disabled(id == nil)
        Button("Open .md in Text Editor") { model.openInTextEditor(id, markdown: true) }
            .disabled(id == nil)
        Divider()
        Button(hasPDF ? "Replace PDF\u{2026}" : "Link PDF\u{2026}") { model.attachFulltext(.pdf, id: id) }
            .disabled(id == nil)
        Button(hasEPUB ? "Replace EPUB\u{2026}" : "Link EPUB\u{2026}") { model.attachFulltext(.epub, id: id) }
            .disabled(id == nil)
        if hasPDF {
            Button("Remove PDF Link") { model.removeFulltext(.pdf, id: id) }
        }
        if hasEPUB {
            Button("Remove EPUB Link") { model.removeFulltext(.epub, id: id) }
        }
    }
}
