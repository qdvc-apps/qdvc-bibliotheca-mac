import AppKit
import Observation
import UniformTypeIdentifiers
import BibliothecaCore

/// A sidebar filter — the Mac equivalent of the GTK Catalogue's Pane 1 nodes.
enum SidebarItem: Hashable {
    case all
    case type(String)
    case fulltext(FulltextFilter)
    case doi(hasDOI: Bool)
    case work(String)
    case author(String)
    case outlet(String)
}

enum FulltextFilter: Hashable, CaseIterable {
    case pdf, epub, missing
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct InTextCitations: Equatable {
    var parenthetical: String
    var narrative: String
}

/// All UI state for the single main window. Every mutation of the workspace
/// goes through here so the rows, sidebar counts and detail pane stay in step.
@MainActor
@Observable
final class AppModel {
    // Workspace
    private(set) var workspace: Workspace?
    private(set) var isLoading = false
    var alert: AlertInfo?
    private(set) var recentWorkspaces: [String] = Prefs.recentWorkspaces

    // Pane 1
    var sidebarSelection: SidebarItem? = .all
    private(set) var works: [MyWork] = []
    private(set) var starredAuthors: [Author] = []
    private(set) var starredOutlets: [Outlet] = []
    private(set) var sidebarCounts: [SidebarItem: Int] = [:]

    // Pane 2
    var searchText = ""
    var sortOrder: [KeyPathComparator<CatalogueRow>] = [KeyPathComparator(\CatalogueRow.id)]
    private(set) var rows: [CatalogueRow] = []
    var selectedID: String?

    // Pane 3
    var citationStyle = CitationStyle.apa
    private(set) var referenceMarkup = ""
    private(set) var referencePlain = ""
    private(set) var inText: InTextCitations?
    private(set) var notesText = ""
    private(set) var notesRecordID: String?
    private(set) var notesDirty = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    var quickLookURL: URL?

    /// Bumped whenever a record's full-text links change. `Record` itself is not
    /// observable, so views that show link state read this to re-render.
    private(set) var fulltextRevision = 0

    // MARK: - Derived

    var selectedRecord: Record? {
        guard let id = selectedID else { return nil }
        return workspace?.record(id)
    }

    var windowTitle: String {
        workspace?.root.lastPathComponent ?? "QDVC Bibliotheca"
    }

    var statusLine: String {
        guard let ws = workspace else { return "" }
        let total = ws.records.count
        return rows.count == total ? "\(total) records" : "\(rows.count) of \(total) records"
    }

    func hasFulltext(_ kind: FulltextKind, id: String?) -> Bool {
        _ = fulltextRevision
        guard let id, let rec = workspace?.record(id) else { return false }
        return kind == .pdf ? rec.hasPDF : rec.hasEPUB
    }

    // MARK: - Launch

    func startUp() {
        guard workspace == nil, !isLoading, Prefs.reopenLast,
              let last = Prefs.lastWorkspace else { return }
        let url = URL(fileURLWithPath: last, isDirectory: true)
        if Workspace.looksLikeWorkspace(url) { open(url) }
    }

    // MARK: - Opening and closing

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a Bibliotheca workspace folder (the one containing bibtex/ and markdown/)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        let root = url.standardizedFileURL
        guard directoryExists(root) else {
            alert = AlertInfo(title: "Folder Not Found", message: "\(root.path) no longer exists.")
            removeRecent(root.path)
            return
        }
        if !Workspace.looksLikeWorkspace(root) {
            guard confirmInitialise(root) else { return }
            do {
                try Workspace.initialise(at: root)
            } catch {
                alert = AlertInfo(title: "Could Not Create Workspace", message: error.localizedDescription)
                return
            }
        }
        flushNotes()
        load(root, forceRescan: false, preserveState: false)
    }

    func closeWorkspace() {
        flushNotes()
        workspace = nil
        selectedID = nil
        sidebarSelection = .all
        searchText = ""
        clearDetail()
        refreshSidebar()
        refreshRows()
    }

    /// Reload from disk (only changed files are re-parsed), keeping the
    /// current filter and selection.
    func refresh(fullRescan: Bool = false) {
        guard let ws = workspace, !isLoading else { return }
        flushNotes()
        load(ws.root, forceRescan: fullRescan, preserveState: true)
    }

    func clearRecents() {
        recentWorkspaces = []
        Prefs.recentWorkspaces = []
    }

    private func load(_ root: URL, forceRescan: Bool, preserveState: Bool) {
        isLoading = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> Workspace in
                let ws = Workspace(root: root)
                ws.load(forceRescan: forceRescan)
                return ws
            }.value
            install(loaded, preserveState: preserveState)
        }
    }

    private func install(_ ws: Workspace, preserveState: Bool) {
        let sameWorkspace = workspace?.root == ws.root
        workspace = ws
        isLoading = false
        pushRecent(ws.root.path)
        Prefs.lastWorkspace = ws.root.path
        citationStyle = Prefs.citationStyle(for: ws.root)
        if citationStyle != CitationStyle.apa && citationStyle != CitationStyle.acis {
            // CSL styles are not supported in the Mac app yet.
            citationStyle = CitationStyle.apa
        }

        if preserveState && sameWorkspace {
            if let item = sidebarSelection, !isValid(item, in: ws) { sidebarSelection = .all }
            if let id = selectedID, ws.record(id) == nil { selectedID = nil }
        } else {
            sidebarSelection = .all
            selectedID = nil
            searchText = ""
        }
        refreshSidebar()
        refreshRows()
        // Write any notes typed while loading, then show the fresh detail.
        flushNotes()
        loadDetail()
    }

    private func isValid(_ item: SidebarItem, in ws: Workspace) -> Bool {
        switch item {
        case .work(let key): return ws.myWorks[key] != nil
        case .author(let id): return ws.authors[id]?.starred == true
        case .outlet(let id): return ws.outlets[id]?.starred == true
        default: return true
        }
    }

    private func confirmInitialise(_ root: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(root.lastPathComponent)\u{201D} is not a Bibliotheca workspace."
        alert.informativeText = "It has no bibtex or markdown folder. Create an empty workspace in this folder?"
        alert.addButton(withTitle: "Create Workspace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func pushRecent(_ path: String) {
        var list = recentWorkspaces.filter { $0 != path }
        list.insert(path, at: 0)
        recentWorkspaces = Array(list.prefix(10))
        Prefs.recentWorkspaces = recentWorkspaces
    }

    private func removeRecent(_ path: String) {
        recentWorkspaces.removeAll { $0 == path }
        Prefs.recentWorkspaces = recentWorkspaces
    }

    // MARK: - Pane 1: sidebar

    func refreshSidebar() {
        guard let ws = workspace else {
            works = []
            starredAuthors = []
            starredOutlets = []
            sidebarCounts = [:]
            return
        }
        works = ws.myWorks.values.sorted { a, b in
            let (na, nb) = (a.name.lowercased(), b.name.lowercased())
            return na != nb ? na < nb : a.key < b.key
        }
        starredAuthors = ws.starredAuthors()
        starredOutlets = ws.starredOutlets()

        let all = Array(ws.records.values)
        var counts: [SidebarItem: Int] = [.all: all.count]
        for label in Builtin.typeOrder {
            counts[.type(label)] = all.filter { $0.typeLabel == label }.count
        }
        counts[.fulltext(.pdf)] = all.filter(\.hasPDF).count
        counts[.fulltext(.epub)] = all.filter(\.hasEPUB).count
        counts[.fulltext(.missing)] = all.filter { !$0.hasPDF && !$0.hasEPUB }.count
        counts[.doi(hasDOI: true)] = all.filter { !$0.doi.isEmpty }.count
        counts[.doi(hasDOI: false)] = all.filter { $0.doi.isEmpty }.count
        for w in works { counts[.work(w.key)] = ws.recordsForWork(w.key).count }
        for a in starredAuthors { counts[.author(a.authorID)] = a.recordIDs.count }
        for o in starredOutlets { counts[.outlet(o.outletID)] = o.recordIDs.count }
        sidebarCounts = counts
    }

    func title(for item: SidebarItem) -> String {
        switch item {
        case .all: return "All Records"
        case .type(let label): return label
        case .fulltext(.pdf): return "PDF Available"
        case .fulltext(.epub): return "EPUB Available"
        case .fulltext(.missing): return "No Full Text"
        case .doi(let has): return has ? "DOI Set" : "DOI Not Set"
        case .work(let key): return workspace?.myWorks[key]?.name ?? key
        case .author(let id): return workspace?.authors[id]?.displayName ?? id
        case .outlet(let id):
            guard let o = workspace?.outlets[id] else { return id }
            return o.nickname.isEmpty ? o.name : o.nickname
        }
    }

    func icon(for item: SidebarItem) -> String {
        switch item {
        case .all: return "books.vertical"
        case .type(let label):
            switch label {
            case "Journal article": return "newspaper"
            case "Proceedings": return "person.3"
            case "Book chapter": return "book.pages"
            case "Book": return "book.closed"
            case "Webpage": return "globe"
            default: return "doc"
            }
        case .fulltext(.pdf): return "doc.richtext"
        case .fulltext(.epub): return "book"
        case .fulltext(.missing): return "doc.badge.ellipsis"
        case .doi(let has): return has ? "link" : "link.badge.plus"
        case .work: return "folder"
        case .author: return "person"
        case .outlet: return "building.columns"
        }
    }

    // MARK: - Pane 2: rows

    func refreshRows() {
        guard let ws = workspace else {
            rows = []
            return
        }
        let records: [Record]
        switch sidebarSelection ?? .all {
        case .all: records = ws.allRecords()
        case .type(let label): records = ws.recordsByType(label)
        case .fulltext(.pdf): records = ws.recordsByFulltext(.pdf)
        case .fulltext(.epub): records = ws.recordsByFulltext(.epub)
        case .fulltext(.missing): records = ws.recordsByFulltext(nil)
        case .doi(let has): records = ws.recordsByDOIStatus(hasDOI: has)
        case .work(let key): records = ws.recordsForWork(key)
        case .author(let id): records = ws.recordsForAuthor(id)
        case .outlet(let id): records = ws.recordsForOutlet(id)
        }
        let priority = Prefs.jflagPriority()
        var built = records.map { CatalogueRow($0, outlet: ws.outlet(for: $0), jflagPriority: priority) }
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty { built = built.filter { $0.matches(needle) } }
        if !sortOrder.isEmpty { built.sort(using: sortOrder) }
        rows = built
    }

    // MARK: - Pane 3: detail

    func selectionChanged() {
        guard selectedID != notesRecordID else { return }
        flushNotes()
        loadDetail()
    }

    private func clearDetail() {
        notesRecordID = nil
        notesText = ""
        notesDirty = false
        referenceMarkup = ""
        referencePlain = ""
        inText = nil
    }

    private func loadDetail() {
        guard let ws = workspace, let rec = selectedRecord else {
            clearDetail()
            return
        }
        let note = ws.readNotes(rec)
        notesRecordID = rec.bibliothecaID
        notesText = note.body
        notesDirty = false
        renderReference()
    }

    func citationStyleChanged() {
        if let ws = workspace { Prefs.setCitationStyle(citationStyle, for: ws.root) }
        renderReference()
    }

    private func renderReference() {
        guard let ws = workspace, let rec = selectedRecord else {
            referenceMarkup = ""
            referencePlain = ""
            inText = nil
            return
        }
        if citationStyle == CitationStyle.acis {
            let letter = ws.acisDisambiguator(rec)
            referenceMarkup = rec.acisMarkup(disambiguator: letter)
            referencePlain = rec.acisPlain(disambiguator: letter)
            inText = InTextCitations(parenthetical: rec.acisInText(disambiguator: letter),
                                     narrative: rec.acisInText(disambiguator: letter, narrative: true))
        } else {
            referenceMarkup = rec.apaMarkup()
            referencePlain = rec.apaPlain()
            inText = nil
        }
    }

    // MARK: - Notes

    func notesEdited(_ text: String) {
        guard notesRecordID != nil, text != notesText else { return }
        notesText = text
        notesDirty = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.flushNotes()
        }
    }

    /// Write pending notes for the record they belong to. Called on record
    /// switch, before any frontmatter write, on refresh/close and on quit.
    func flushNotes() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard notesDirty, let ws = workspace, let id = notesRecordID, let rec = ws.record(id) else {
            notesDirty = false
            return
        }
        do {
            try ws.writeNotes(rec, body: notesText)
            notesDirty = false
        } catch {
            alert = AlertInfo(title: "Could Not Save Notes", message: error.localizedDescription)
        }
    }

    /// Pick up notes edited in another app while we were in the background.
    func appBecameActive() {
        guard !notesDirty, let ws = workspace, let id = notesRecordID, let rec = ws.record(id) else { return }
        let body = ws.readNotes(rec).body
        if body != notesText { notesText = body }
    }

    // MARK: - Record actions

    private func record(_ id: String?) -> Record? {
        guard let id else { return nil }
        return workspace?.record(id)
    }

    func copyReference(rich: Bool) {
        guard selectedRecord != nil else { return }
        if rich {
            Platform.copyRich(markup: referenceMarkup, plain: referencePlain)
        } else {
            Platform.copyPlain(referencePlain)
        }
    }

    func copyInText(narrative: Bool) {
        guard let cites = inText else { return }
        Platform.copyPlain(narrative ? cites.narrative : cites.parenthetical)
    }

    func copyID(_ id: String?) {
        guard let rec = record(id) else { return }
        Platform.copyPlain(rec.bibliothecaID)
    }

    func fulltextURL(_ kind: FulltextKind, id: String?) -> URL? {
        guard let ws = workspace, let rec = record(id) else { return nil }
        return ws.resolveFulltextPath(rec.bibliothecaID, kind: kind, storageRoot: Prefs.fulltextRoot)
    }

    func openFulltext(_ kind: FulltextKind, id: String?) {
        guard let url = fulltextURL(kind, id: id) else { return }
        guard fileExists(url) else {
            alert = AlertInfo(title: "\(kind.label) Not Found",
                              message: "The linked file could not be found:\n\(url.path)")
            return
        }
        Platform.open(url)
    }

    /// Double-click: open the PDF (else EPUB) when one is linked.
    func primaryAction(_ ids: Set<String>) {
        guard let id = ids.first else { return }
        if hasFulltext(.pdf, id: id) {
            openFulltext(.pdf, id: id)
        } else if hasFulltext(.epub, id: id) {
            openFulltext(.epub, id: id)
        }
    }

    func quickLook(_ id: String?) {
        let kind: FulltextKind = hasFulltext(.pdf, id: id) ? .pdf : .epub
        guard let url = fulltextURL(kind, id: id), fileExists(url) else {
            NSSound.beep()
            return
        }
        quickLookURL = url
    }

    func attachFulltext(_ kind: FulltextKind, id: String?) {
        guard let ws = workspace, let rec = record(id) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = kind == .pdf ? [UTType.pdf] : [UTType.epub]
        panel.message = "Choose the \(kind.label) for \(rec.bibliothecaID)"
        panel.prompt = "Link \(kind.label)"
        if let root = Prefs.fulltextRoot { panel.directoryURL = root }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFulltext(kind, file: url, for: rec, in: ws)
    }

    func removeFulltext(_ kind: FulltextKind, id: String?) {
        guard let ws = workspace, let rec = record(id) else { return }
        setFulltext(kind, file: nil, for: rec, in: ws)
    }

    private func setFulltext(_ kind: FulltextKind, file: URL?, for rec: Record, in ws: Workspace) {
        // Critical ordering rule: notes and frontmatter share one file, so
        // pending notes are written before the frontmatter is touched.
        flushNotes()
        do {
            try ws.setFulltextPath(rec.bibliothecaID, kind: kind, file: file, storageRoot: Prefs.fulltextRoot)
        } catch {
            alert = AlertInfo(title: "Could Not Update \(kind.label) Link", message: error.localizedDescription)
        }
        fulltextRevision += 1
        refreshSidebar()
        refreshRows()
    }

    func revealInFinder(_ id: String?, markdown: Bool) {
        guard let rec = record(id) else { return }
        let url = markdown ? rec.mdURL : rec.bibURL
        if fileExists(url) {
            Platform.revealInFinder(url)
        } else {
            Platform.revealInFinder(url.deletingLastPathComponent())
        }
    }

    func openInTextEditor(_ id: String?, markdown: Bool) {
        guard let ws = workspace, let rec = record(id) else { return }
        flushNotes()
        let url = markdown ? rec.mdURL : rec.bibURL
        if markdown && !fileExists(url) {
            do {
                try ws.writeNotes(rec, body: "")
            } catch {
                alert = AlertInfo(title: "Could Not Create Notes File", message: error.localizedDescription)
                return
            }
        }
        Platform.openInTextEditor(url)
    }
}
