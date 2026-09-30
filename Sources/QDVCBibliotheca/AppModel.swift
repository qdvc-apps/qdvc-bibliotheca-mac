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

/// What the Import BibTeX sheet opens with.
struct ImportRequest: Identifiable {
    let id = UUID()
    var text: String = ""
    /// Where the text came from (a file name), shown in the sheet.
    var sourceName: String?
    /// The work to preselect in "Allocate imported records to".
    var workKey: String?
}

/// The window's top-level tabs (the segmented control in the toolbar).
enum AppTab: String, CaseIterable, Identifiable {
    case catalogue, authors, outlets, doiLookup

    var id: Self { self }

    var title: String {
        switch self {
        case .catalogue: return "Catalogue"
        case .authors: return "Authors"
        case .outlets: return "Outlets"
        case .doiLookup: return "DOI Lookup"
        }
    }
}

/// The one sheet that can be open over the main window.
enum ActiveSheet: Identifiable {
    case importBibTeX(ImportRequest)
    case allocate([String])
    case newWork(allocating: [String])
    case rename(String)
    case nickname(String)
    case jflags(String)

    var id: String {
        switch self {
        case .importBibTeX(let request): return "import-\(request.id)"
        case .allocate(let ids): return "allocate-" + ids.joined(separator: ",")
        case .newWork: return "new-work"
        case .rename(let id): return "rename-\(id)"
        case .nickname(let id): return "nickname-\(id)"
        case .jflags(let id): return "jflags-\(id)"
        }
    }
}

/// A row of the Authors tab.
struct AuthorRow: Identifiable, Hashable {
    let id: String
    let name: String
    let starred: Bool
    let count: Int

    var starRank: Int { starred ? 0 : 1 }
}

/// A row of the Outlets tab.
struct OutletRow: Identifiable, Hashable {
    let id: String
    let name: String
    let nickname: String
    let jflags: String
    let starred: Bool
    let count: Int

    var starRank: Int { starred ? 0 : 1 }
}

enum DOILookupOutcome: Equatable {
    case found(String)
    case notFound(String)
    case empty
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
    var currentTab: AppTab = .catalogue
    var activeSheet: ActiveSheet?

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

    // Authors tab
    var authorSearchText = ""
    var authorsStarredOnly = false
    var authorSortOrder: [KeyPathComparator<AuthorRow>] = [KeyPathComparator(\AuthorRow.name)]
    private(set) var authorRows: [AuthorRow] = []
    var selectedAuthorID: String?

    // Outlets tab
    var outletSearchText = ""
    var outletsStarredOnly = false
    var outletSortOrder: [KeyPathComparator<OutletRow>] = [KeyPathComparator(\OutletRow.name)]
    private(set) var outletRows: [OutletRow] = []
    var selectedOutletID: String?

    // DOI Lookup tab
    var doiQuery = ""
    private(set) var doiOutcome: DOILookupOutcome?

    /// A short-lived message shown in the window subtitle.
    private(set) var statusMessage: String?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

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
        if let statusMessage { return statusMessage }
        guard let ws = workspace else { return "" }
        func counted(_ shown: Int, _ total: Int, _ noun: String) -> String {
            shown == total ? "\(total) \(noun)" : "\(shown) of \(total) \(noun)"
        }
        switch currentTab {
        case .catalogue: return counted(rows.count, ws.records.count, "records")
        case .authors: return counted(authorRows.count, ws.authors.count, "authors")
        case .outlets: return counted(outletRows.count, ws.outlets.count, "outlets")
        case .doiLookup: return "\(ws.records.count) records"
        }
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
        activeSheet = nil
        workspace = nil
        selectedID = nil
        sidebarSelection = .all
        searchText = ""
        clearDetail()
        refreshSidebar()
        refreshRows()
        refreshAuthorRows()
        refreshOutletRows()
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
            selectedAuthorID = nil
            selectedOutletID = nil
            doiOutcome = nil
        }
        refreshSidebar()
        refreshRows()
        refreshAuthorRows()
        refreshOutletRows()
        // Write any notes typed while loading, then show the fresh detail.
        flushNotes()
        loadDetail()
    }

    private func isValid(_ item: SidebarItem, in ws: Workspace) -> Bool {
        switch item {
        case .work(let key): return ws.myWorks[key] != nil
        case .author(let id): return ws.authors[id] != nil
        case .outlet(let id): return ws.outlets[id] != nil
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

    // MARK: - Import

    /// The work currently shown in the sidebar, if any.
    var currentWorkKey: String? {
        if case .work(let key) = sidebarSelection { return key }
        return nil
    }

    /// Open the Import BibTeX sheet, preselecting the work being viewed.
    func beginImport(text: String = "", sourceName: String? = nil) {
        guard workspace != nil, !isLoading else { return }
        activeSheet = .importBibTeX(ImportRequest(text: text, sourceName: sourceName, workKey: currentWorkKey))
    }

    /// Open the sheet pre-filled with dropped `.bib` files. Returns false when
    /// none of the URLs is a readable `.bib` file.
    @discardableResult
    func beginImport(files: [URL]) -> Bool {
        let bibs = files.filter { $0.pathExtension.lowercased() == "bib" }
        let texts = bibs.compactMap { url -> String? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        guard workspace != nil, !texts.isEmpty else { return false }
        let name = bibs.count == 1 ? bibs[0].lastPathComponent : "\(bibs.count) files"
        beginImport(text: texts.joined(separator: "\n\n"), sourceName: name)
        return true
    }

    /// Import the sheet's BibTeX, optionally allocating the new records to a
    /// work, then show the result.
    func performImport(text: String, allocateTo workKey: String?) {
        guard let ws = workspace else { return }
        activeSheet = nil
        let entryCount = BibTeX.splitEntries(text).count
        let result: Workspace.ImportResult
        do {
            result = try ws.importBibText(text)
        } catch {
            alert = AlertInfo(title: "Import Failed", message: error.localizedDescription)
            return
        }

        var allocated = 0
        var allocationError: String?
        if let key = workKey, ws.myWorks[key] != nil, !result.imported.isEmpty {
            do {
                allocated = try ws.allocateToWork(key, ids: result.imported)
            } catch {
                allocationError = error.localizedDescription
            }
        }

        // Show the result: the work the records went to, with the first new
        // record selected (falling back to All Records if the current filter
        // would hide it).
        refreshSidebar()
        if allocated > 0, let key = workKey { sidebarSelection = .work(key) }
        currentTab = .catalogue
        refreshRows()
        refreshAuthorRows()
        refreshOutletRows()
        let firstNew = result.imported.sorted { $0.lowercased() < $1.lowercased() }.first
        if let firstNew {
            if !rows.contains(where: { $0.id == firstNew }) {
                sidebarSelection = .all
                searchText = ""
                refreshRows()
            }
            selectedID = firstNew
        }

        let n = result.imported.count
        var summary = "Imported \(n) record\(n == 1 ? "" : "s")."
        if allocated > 0, let key = workKey, let work = ws.myWorks[key] {
            summary += " Allocated \(allocated) to \u{201C}\(work.name)\u{201D}."
        }
        let skippedExisting = max(0, entryCount - n - result.skippedDOIs.count)

        var problems: [String] = []
        if !result.skippedDOIs.isEmpty {
            problems.append("Skipped because their DOI is already in the library:")
            problems += result.skippedDOIs.map {
                "\u{2022} \($0.citationKey): DOI \($0.doi) is used by \($0.existingID)"
            }
        }
        if skippedExisting > 0 {
            problems.append("Skipped \(skippedExisting) entr\(skippedExisting == 1 ? "y" : "ies") whose Bibliotheca ID already exists (or that have no citation key).")
        }
        if let allocationError {
            problems.append("The records were imported but could not be allocated: \(allocationError)")
        }

        if problems.isEmpty && n > 0 {
            showStatus(summary)
        } else {
            alert = AlertInfo(title: n > 0 ? "Import Finished with Warnings" : "Nothing Imported",
                              message: ([summary] + problems).joined(separator: "\n\n"))
        }
    }

    func showStatus(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
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
        if case .author(let id)? = sidebarSelection, let a = ws.authors[id] {
            counts[.author(id)] = a.recordIDs.count
        }
        if case .outlet(let id)? = sidebarSelection, let o = ws.outlets[id] {
            counts[.outlet(id)] = o.recordIDs.count
        }
        sidebarCounts = counts
    }

    /// An author or outlet shown in the Catalogue although it is not starred
    /// (after "Show in Catalogue"); the sidebar lists it under Query Results,
    /// like the GTK app's transient node.
    var transientSidebarItem: SidebarItem? {
        guard let ws = workspace, let item = sidebarSelection else { return nil }
        switch item {
        case .author(let id):
            if let a = ws.authors[id], !a.starred { return item }
        case .outlet(let id):
            if let o = ws.outlets[id], !o.starred { return item }
        default:
            break
        }
        return nil
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

    // MARK: - Navigation between tabs

    /// Show a record in the Catalogue, widening the filter if it is hidden.
    func revealRecord(_ id: String) {
        guard workspace?.record(id) != nil else { return }
        currentTab = .catalogue
        if !rows.contains(where: { $0.id == id }) {
            sidebarSelection = .all
            searchText = ""
            refreshSidebar()
            refreshRows()
        }
        selectedID = id
    }

    func showAuthorWorks(_ authorID: String?) {
        guard let authorID, workspace?.authors[authorID] != nil else { return }
        currentTab = .catalogue
        searchText = ""
        sidebarSelection = .author(authorID)
        refreshSidebar()
        refreshRows()
    }

    func showOutletWorks(_ outletID: String?) {
        guard let outletID, workspace?.outlets[outletID] != nil else { return }
        currentTab = .catalogue
        searchText = ""
        sidebarSelection = .outlet(outletID)
        refreshSidebar()
        refreshRows()
    }

    /// The outlet a record belongs to (journal articles and proceedings).
    func outletID(forRecord id: String?) -> String? {
        guard let ws = workspace, let rec = record(id) else { return nil }
        return ws.outlet(for: rec)?.outletID
    }

    /// Jump to the Outlets tab with the given outlet selected.
    func revealOutlet(_ outletID: String?) {
        guard let outletID, workspace?.outlets[outletID] != nil else { return }
        currentTab = .outlets
        outletSearchText = ""
        outletsStarredOnly = false
        refreshOutletRows()
        selectedOutletID = outletID
    }

    // MARK: - Authors tab

    func refreshAuthorRows() {
        guard let ws = workspace else {
            authorRows = []
            return
        }
        let needle = authorSearchText.trimmed
        var built = ws.allAuthors().map {
            AuthorRow(id: $0.authorID, name: $0.displayName, starred: $0.starred, count: $0.recordIDs.count)
        }
        if authorsStarredOnly { built = built.filter(\.starred) }
        if !needle.isEmpty {
            built = built.filter {
                $0.name.localizedCaseInsensitiveContains(needle) || $0.id.localizedCaseInsensitiveContains(needle)
            }
        }
        if !authorSortOrder.isEmpty { built.sort(using: authorSortOrder) }
        authorRows = built
    }

    func setAuthorStarred(_ authorID: String, _ starred: Bool) {
        guard let ws = workspace else { return }
        do {
            try ws.setAuthorStarred(authorID, starred)
        } catch {
            alert = AlertInfo(title: "Could Not Update Author", message: error.localizedDescription)
        }
        refreshSidebar()
        refreshAuthorRows()
    }

    // MARK: - Outlets tab

    func refreshOutletRows() {
        guard let ws = workspace else {
            outletRows = []
            return
        }
        let priority = Prefs.jflagPriority()
        let needle = outletSearchText.trimmed
        var built = ws.allOutlets().map { o -> OutletRow in
            let flags = CatalogueSupport.orderJflags(o.sortedJflags(), priority: priority)
            return OutletRow(id: o.outletID, name: o.name, nickname: o.nickname,
                             jflags: flags.joined(separator: ", "), starred: o.starred,
                             count: o.recordIDs.count)
        }
        if outletsStarredOnly { built = built.filter(\.starred) }
        if !needle.isEmpty {
            built = built.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || $0.nickname.localizedCaseInsensitiveContains(needle)
            }
        }
        if !outletSortOrder.isEmpty { built.sort(using: outletSortOrder) }
        outletRows = built
    }

    func setOutletStarred(_ outletID: String, _ starred: Bool) {
        guard let ws = workspace else { return }
        do {
            try ws.setOutletStarred(outletID, starred)
        } catch {
            alert = AlertInfo(title: "Could Not Update Outlet", message: error.localizedDescription)
        }
        refreshSidebar()
        refreshOutletRows()
    }

    func beginSetNickname(_ outletID: String?) {
        guard let outletID, workspace?.outlets[outletID] != nil else { return }
        activeSheet = .nickname(outletID)
    }

    /// Throws (with a user-facing message) on an invalid or duplicate nickname,
    /// so the sheet can stay open and show the problem.
    func setOutletNickname(_ outletID: String, _ nickname: String) throws {
        guard let ws = workspace else { return }
        try ws.setOutletNickname(outletID, nickname)
        activeSheet = nil
        refreshSidebar()
        refreshOutletRows()
        refreshRows()
    }

    func beginSetJflags(_ outletID: String?) {
        guard let outletID, workspace?.outlets[outletID] != nil else { return }
        activeSheet = .jflags(outletID)
    }

    func setOutletJflags(_ outletID: String, _ flags: [String]) {
        guard let ws = workspace else { return }
        activeSheet = nil
        do {
            try ws.setOutletJflags(outletID, flags)
        } catch {
            alert = AlertInfo(title: "Could Not Update J-Flags", message: error.localizedDescription)
        }
        refreshOutletRows()
        refreshRows()
    }

    /// Called by Settings when the J-Flag presets (display priorities) change.
    func jflagPresetsChanged() {
        refreshRows()
        refreshOutletRows()
    }

    // MARK: - DOI Lookup tab

    /// Look the DOI up and, like the GTK app, jump straight to the record.
    func lookupDOI() {
        let raw = doiQuery.trimmed
        guard !raw.isEmpty else {
            doiOutcome = .empty
            return
        }
        guard let ws = workspace else { return }
        if let id = ws.lookupDOI(raw) {
            doiOutcome = .found(id)
            revealRecord(id)
        } else {
            doiOutcome = .notFound(Naming.normaliseDOI(raw))
        }
    }

    // MARK: - My Works

    func beginAllocate(_ ids: [String]) {
        let valid = ids.filter { workspace?.record($0) != nil }
        guard !valid.isEmpty else { return }
        activeSheet = .allocate(valid)
    }

    /// Add records to the chosen works, creating a new work first if named.
    func performAllocate(ids: [String], to workKeys: [String], newWorkName: String) {
        guard let ws = workspace else { return }
        activeSheet = nil
        var targets = workKeys
        do {
            let name = newWorkName.trimmed
            if !name.isEmpty {
                targets.append(try ws.createMyWork(named: name).key)
            }
            var added = 0
            for key in targets {
                added += try ws.allocateToWork(key, ids: ids)
            }
            refreshSidebar()
            refreshRows()
            let what = ids.count == 1 ? ids[0] : "\(ids.count) records"
            if added == 0 {
                showStatus("No change: the chosen works already include \(what).")
            } else if targets.count == 1, let work = ws.myWorks[targets[0]] {
                showStatus("Added \(what) to \u{201C}\(work.name)\u{201D}.")
            } else {
                showStatus("Added \(what) to \(targets.count) works.")
            }
        } catch {
            refreshSidebar()
            refreshRows()
            alert = AlertInfo(title: "Could Not Allocate", message: error.localizedDescription)
        }
    }

    /// Open the New Work sheet; `allocating` lists records the sheet may offer
    /// to add to the new work straight away.
    func beginNewWork(allocating ids: [String] = []) {
        guard workspace != nil, !isLoading else { return }
        activeSheet = .newWork(allocating: ids.filter { workspace?.record($0) != nil })
    }

    /// Create a work, optionally add records to it, and show it.
    func createWork(named name: String, allocating ids: [String]) {
        guard let ws = workspace else { return }
        activeSheet = nil
        do {
            let work = try ws.createMyWork(named: name.trimmed)
            if !ids.isEmpty { try ws.allocateToWork(work.key, ids: ids) }
            currentTab = .catalogue
            searchText = ""
            sidebarSelection = .work(work.key)
            refreshSidebar()
            refreshRows()
            if let first = ids.first { selectedID = first }
            showStatus("Created \u{201C}\(work.name)\u{201D}.")
        } catch {
            alert = AlertInfo(title: "Could Not Create Work", message: error.localizedDescription)
        }
    }

    func revealWork(_ key: String) {
        guard let work = workspace?.myWorks[key] else { return }
        Platform.revealInFinder(work.url)
    }

    func openWorkInTextEditor(_ key: String) {
        guard let work = workspace?.myWorks[key] else { return }
        Platform.openInTextEditor(work.url)
    }

    // MARK: - Rename

    func beginRename(_ id: String?) {
        guard let id, workspace?.record(id) != nil else { return }
        activeSheet = .rename(id)
    }

    /// Why `newID` cannot be used, or nil if it can (or is unchanged).
    func renameProblem(from oldID: String, to newID: String) -> String? {
        let candidate = newID.trimmed
        if candidate.isEmpty { return "Enter a Bibliotheca ID." }
        if candidate == oldID { return nil }
        if Naming.sanitiseID(candidate) != candidate {
            return "Only letters, digits, hyphens (-) and underscores (_) are allowed."
        }
        if workspace?.record(candidate) != nil {
            return "A record named \u{201C}\(candidate)\u{201D} already exists."
        }
        return nil
    }

    /// An ID whose suffix matches the record's outlet nickname, when the
    /// current one doesn't (the convention the Validate report checks).
    func suggestedID(for id: String) -> String? {
        guard let ws = workspace, let rec = ws.record(id), let outlet = ws.outlet(for: rec),
              !outlet.nickname.isEmpty else { return nil }
        let suffix = Naming.idSuffix(id)
        guard suffix != outlet.nickname else { return nil }
        var base = id
        if !suffix.isEmpty, let underscore = id.lastIndex(of: "_") {
            base = String(id[..<underscore])
        }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let candidate = "\(base)_\(outlet.nickname)"
        return ws.record(candidate) == nil ? candidate : nil
    }

    /// Rename a record. Throws so the sheet can show the problem and stay open.
    func performRename(from oldID: String, to newIDRaw: String) throws {
        guard let ws = workspace else { return }
        let newID = newIDRaw.trimmed
        // The notes file is about to move: write pending notes to it first.
        flushNotes()
        try ws.renameRecord(oldID, to: newID)
        activeSheet = nil
        if notesRecordID == oldID { notesRecordID = newID }
        if selectedID == oldID { selectedID = newID }
        refreshSidebar()
        refreshRows()
        refreshAuthorRows()
        refreshOutletRows()
        revealRecord(newID)
        showStatus("Renamed \u{201C}\(oldID)\u{201D} to \u{201C}\(newID)\u{201D}.")
    }
}
