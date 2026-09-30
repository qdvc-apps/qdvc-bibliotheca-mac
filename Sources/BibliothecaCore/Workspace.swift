import Foundation

public struct WorkspaceError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum FulltextKind: String, CaseIterable {
    case pdf
    case epub

    public var label: String { rawValue.uppercased() }
}

/// The workspace model — a port of `qdvc/workspace.py`.
///
/// ```
/// (root)/
///     bibtex/<A..Z>/<bibliotheca_id>.bib     one entry per file, authoritative
///     markdown/<A..Z>/<bibliotheca_id>.md    YAML frontmatter + notes
///     my_works/*.yml                         the user's own works
///     authors/<SURNAME_GivenNames>.yml       derived authors + star state
///     outlets/<nickname-or-slug>.yml         derived outlets + user state
///     csl/*.csl                              optional CSL styles
/// ```
///
/// Differences from the Python model, all deliberate:
/// * The index cache lives in `~/Library/Caches`, not in the workspace, so a
///   synced workspace is never rewritten just because a different machine
///   (or the Linux app, which keeps `.qdvc-index.json`) opened it.
/// * The cache is validated per file by modification time, so records added
///   or edited outside the app show up without a manual full rescan.
/// * Hidden folders (e.g. Syncthing's `.stversions`) are not scanned.
/// * A `my_works` file whose YAML fails to parse is left alone rather than
///   being rewritten from its file name.
public final class Workspace: @unchecked Sendable {
    public static let outletTypes: Set<String> = ["Journal article", "Proceedings"]

    public let root: URL
    public private(set) var records: [String: Record] = [:]
    public private(set) var myWorks: [String: MyWork] = [:]
    public private(set) var authors: [String: Author] = [:]
    public private(set) var outlets: [String: Outlet] = [:]

    private var doiIndex: [String: String] = [:]
    private var authorRecords: [String: [String]] = [:]
    private var outletRecords: [String: [String]] = [:]
    private var acisCache: (stamp: Int, letters: [String: String])?

    /// Where the index cache is kept; nil disables caching (used by tests).
    public var cacheDirectory: URL?

    public init(root: URL, cacheDirectory: URL? = Workspace.defaultCacheDirectory) {
        self.root = root.standardizedFileURL
        self.cacheDirectory = cacheDirectory
    }

    public static var defaultCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("org.qdvc.Bibliotheca", isDirectory: true)
    }

    // MARK: - Paths

    public var bibtexDir: URL { root.appendingPathComponent("bibtex", isDirectory: true) }
    public var markdownDir: URL { root.appendingPathComponent("markdown", isDirectory: true) }
    public var myWorksDir: URL { root.appendingPathComponent("my_works", isDirectory: true) }
    public var authorsDir: URL { root.appendingPathComponent("authors", isDirectory: true) }
    public var outletsDir: URL { root.appendingPathComponent("outlets", isDirectory: true) }
    public var cslDir: URL { root.appendingPathComponent("csl", isDirectory: true) }

    /// Upper-cased first letter of the id, or "_" when it is not a letter.
    func shard(_ bibliothecaID: String) -> String {
        guard let first = bibliothecaID.first else { return "_" }
        let c = String(first).uppercased()
        return c.allSatisfy(\.isLetter) ? c : "_"
    }

    public func bibURL(for id: String) -> URL {
        bibtexDir.appendingPathComponent(shard(id), isDirectory: true)
            .appendingPathComponent("\(id).bib")
    }

    public func mdURL(for id: String) -> URL {
        markdownDir.appendingPathComponent(shard(id), isDirectory: true)
            .appendingPathComponent("\(id).md")
    }

    /// The outlet's YAML path: the nickname when set, else the slug.
    public func outletURL(for outlet: Outlet) -> URL {
        outletURL(nickname: outlet.nickname, outletID: outlet.outletID)
    }

    func outletURL(nickname: String, outletID: String) -> URL {
        var stem = nickname.isEmpty ? outletID : Naming.sanitiseStem(nickname)
        if stem.isEmpty { stem = "outlet" }
        return outletsDir.appendingPathComponent("\(stem).yml")
    }

    /// CSL style file names in `csl/`, sorted case-insensitively.
    public func cslFiles() -> [String] {
        filesIn(cslDir, withExtension: "csl").map(\.lastPathComponent)
            .stableSorted { lowerKey($0) < lowerKey($1) }
    }

    // MARK: - Workspace detection / creation

    public static func looksLikeWorkspace(_ root: URL) -> Bool {
        directoryExists(root.appendingPathComponent("bibtex"))
            || directoryExists(root.appendingPathComponent("markdown"))
    }

    /// Create the skeleton folders of a new, empty workspace.
    public static func initialise(at root: URL) throws {
        for name in ["bibtex", "markdown", "my_works"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
    }

    // MARK: - Loading

    /// Load the workspace. Unchanged files are taken from the index cache;
    /// `forceRescan` re-parses everything.
    public func load(forceRescan: Bool = false) {
        scan(useCache: !forceRescan)
        loadMyWorks()
        buildDOIIndex()
        deriveAuthors()
        deriveOutlets()
        saveCache()
    }

    private func scan(useCache: Bool) {
        var cached: [String: CachedRecord] = [:]
        if useCache, let cache = loadCache() {
            for r in cache.records { cached[r.bibPath] = r }
        }
        records.removeAll()
        acisCache = nil
        guard directoryExists(bibtexDir) else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: bibtexDir, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }

        for case let url as URL in walker {
            guard url.pathExtension == "bib" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            let md = mdURL(for: id)
            let bibModified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let mdModified = modificationTime(md)

            if let c = cached[url.path], c.id == id, c.bibModified == bibModified,
               c.mdModified == mdModified {
                let rec = c.makeRecord(bibURL: url, mdURL: md)
                records[id] = rec
                continue
            }

            let entry = BibTeX.parse(fileAt: url) ?? BibEntry()
            var hasPDF = false
            var hasEPUB = false
            if mdModified != nil {
                let note = MarkdownIO.read(md)
                hasPDF = note.frontmatter["pdf"]?.isTruthy ?? false
                hasEPUB = note.frontmatter["epub"]?.isTruthy ?? false
            }
            let rec = Record(bibliothecaID: id, bibURL: url, mdURL: md, entry: entry,
                             hasPDF: hasPDF, hasEPUB: hasEPUB)
            rec.bibModified = bibModified
            rec.mdModified = mdModified
            records[id] = rec
        }
    }

    private func modificationTime(_ url: URL) -> Double? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else { return nil }
        return date.timeIntervalSince1970
    }

    private func refreshModificationTimes(_ rec: Record) {
        rec.bibModified = modificationTime(rec.bibURL) ?? 0
        rec.mdModified = modificationTime(rec.mdURL)
    }

    private func loadMyWorks() {
        myWorks.removeAll()
        let files = filesIn(myWorksDir, withExtension: "yml") + filesIn(myWorksDir, withExtension: "yaml")
        for f in files {
            let stem = f.deletingPathExtension().lastPathComponent
            let raw = readTextLossy(f)
            let parsed = raw.flatMap { YAMLReader.parse($0) }
            let data = parsed ?? .mapping([])

            var citesValue = data["cites"]
            if !(citesValue?.isTruthy ?? false) { citesValue = data["citations"] }
            let cites = (citesValue?.sequenceValue ?? []).map { $0.stringValue ?? "None" }

            var nameValue = data["name"]
            if !(nameValue?.isTruthy ?? false) { nameValue = data["title"] }
            let name = (nameValue?.isTruthy ?? false) ? (nameValue?.stringValue ?? stem) : stem

            var publishedValue = data["published_as"]
            if !(publishedValue?.isTruthy ?? false) { publishedValue = data["published_version"] }
            let publishedAs = (publishedValue?.isTruthy ?? false) ? publishedValue?.stringValue : nil

            let work = MyWork(key: stem, name: name, url: f, cites: cites, publishedAs: publishedAs)
            myWorks[stem] = work

            // Canonicalise (name first, cites de-duplicated and sorted) — but
            // only files we could parse, so a YAML typo never loses data.
            if let parsed, parsed != .mapping(work.yamlPairs()) {
                try? work.save()
            }
        }
    }

    private func buildDOIIndex() {
        doiIndex.removeAll()
        for (id, rec) in records where !rec.doi.isEmpty {
            doiIndex[rec.doi.lowercased()] = id
        }
    }

    // MARK: - Authors

    private func loadAuthorFiles() -> [String: Author] {
        var loaded: [String: Author] = [:]
        let files = filesIn(authorsDir, withExtension: "yml") + filesIn(authorsDir, withExtension: "yaml")
        for f in files {
            guard let raw = readTextLossy(f), let data = YAMLReader.parse(raw),
                  data.mappingValue != nil else { continue }
            let stem = f.deletingPathExtension().lastPathComponent
            let idValue = data["id"]
            let id = (idValue?.isTruthy ?? false) ? (idValue?.stringValue ?? stem) : stem
            loaded[id] = Author(authorID: id,
                                surname: data["surname"]?.stringValue ?? "",
                                givenNames: data["given_names"]?.stringValue ?? "",
                                starred: data["starred"]?.isTruthy ?? false,
                                url: f)
        }
        return loaded
    }

    /// Derive authors from the records, keeping persisted star state and
    /// writing a file for every newly seen author.
    private func deriveAuthors() {
        let persisted = loadAuthorFiles()
        authors = [:]
        authorRecords = [:]
        for (id, rec) in records {
            var seenInRecord = Set<String>()
            for token in Builtin.authorTokens(rec.author) {
                let aid = Naming.makeAuthorID(surname: token.surname, givenNames: token.given)
                guard !aid.isEmpty else { continue }
                if authors[aid] == nil {
                    authors[aid] = persisted[aid] ?? Author(
                        authorID: aid, surname: token.surname, givenNames: token.given,
                        url: authorsDir.appendingPathComponent("\(aid).yml"))
                    authorRecords[aid] = []
                }
                if seenInRecord.insert(aid).inserted {
                    authorRecords[aid, default: []].append(id)
                }
            }
        }
        for (aid, author) in authors {
            if !fileExists(author.url) { try? author.save() }
            author.recordIDs = (authorRecords[aid] ?? []).stableSorted { lowerKey($0) < lowerKey($1) }
        }
    }

    public func allAuthors() -> [Author] {
        authors.values.sorted { a, b in
            let (sa, sb) = (lowerKey(a.surname), lowerKey(b.surname))
            if sa != sb { return sa < sb }
            let (ga, gb) = (lowerKey(a.givenNames), lowerKey(b.givenNames))
            if ga != gb { return ga < gb }
            return a.authorID < b.authorID
        }
    }

    public func starredAuthors() -> [Author] { allAuthors().filter(\.starred) }

    public func setAuthorStarred(_ authorID: String, _ starred: Bool) throws {
        guard let author = authors[authorID] else { return }
        author.starred = starred
        try author.save()
    }

    // MARK: - Outlets

    private func loadOutletFiles() -> [String: Outlet] {
        var loaded: [String: Outlet] = [:]
        let files = filesIn(outletsDir, withExtension: "yml") + filesIn(outletsDir, withExtension: "yaml")
        for f in files {
            guard let raw = readTextLossy(f), let data = YAMLReader.parse(raw),
                  data.mappingValue != nil else { continue }
            let name = (data["name"]?.stringValue ?? "").pyStrip
            guard !name.isEmpty else { continue }
            let oid = Naming.slugifyOutlet(name)
            guard !oid.isEmpty else { continue }
            let flags = (data["jflags"]?.sequenceValue ?? []).compactMap(\.stringValue)
            loaded[oid] = Outlet(outletID: oid, name: name,
                                 nickname: (data["nickname"]?.stringValue ?? "").pyStrip,
                                 starred: data["starred"]?.isTruthy ?? false,
                                 jflags: flags, url: f)
        }
        return loaded
    }

    /// Derive outlets from journal-article and proceedings records only.
    private func deriveOutlets() {
        let persisted = loadOutletFiles()
        outlets = [:]
        outletRecords = [:]
        for (id, rec) in records where Workspace.outletTypes.contains(rec.typeLabel) {
            let name = rec.journal.pyStrip
            guard !name.isEmpty else { continue }
            let oid = Naming.slugifyOutlet(name)
            guard !oid.isEmpty else { continue }
            if outlets[oid] == nil {
                if let existing = persisted[oid] {
                    existing.name = name
                    outlets[oid] = existing
                } else {
                    outlets[oid] = Outlet(outletID: oid, name: name,
                                          url: outletURL(nickname: "", outletID: oid))
                }
                outletRecords[oid] = []
            }
            outletRecords[oid, default: []].append(id)
        }
        for (oid, outlet) in outlets {
            if !fileExists(outlet.url) { try? outlet.save() }
            outlet.recordIDs = (outletRecords[oid] ?? []).stableSorted { lowerKey($0) < lowerKey($1) }
        }
    }

    public func allOutlets() -> [Outlet] {
        outlets.values.sorted { a, b in
            let (na, nb) = (lowerKey(a.name), lowerKey(b.name))
            return na != nb ? na < nb : a.outletID < b.outletID
        }
    }

    public func starredOutlets() -> [Outlet] { allOutlets().filter(\.starred) }

    public func setOutletStarred(_ outletID: String, _ starred: Bool) throws {
        guard let outlet = outlets[outletID] else { return }
        outlet.starred = starred
        try outlet.save()
    }

    public func setOutletJflags(_ outletID: String, _ flags: [String]) throws {
        guard let outlet = outlets[outletID] else { return }
        outlet.jflags = flags
        try outlet.save()
    }

    /// Set or clear a nickname, renaming the outlet's YAML file to match.
    /// Throws on an invalid character or a collision with another outlet.
    public func setOutletNickname(_ outletID: String, _ nickname: String) throws {
        guard let outlet = outlets[outletID] else { return }
        let nick = nickname.pyStrip
        if !nick.isEmpty {
            guard Naming.isValidNickname(nick) else {
                throw WorkspaceError("A nickname may contain only the letters A-Z and a-z.")
            }
            let newStem = nick.lowercased()
            for (otherID, other) in outlets where otherID != outletID {
                if !other.nickname.isEmpty, other.nickname.lowercased() == newStem {
                    throw WorkspaceError("The nickname '\(nick)' is already used by '\(other.name)'.")
                }
                let otherStem = other.nickname.isEmpty ? other.outletID : Naming.sanitiseStem(other.nickname)
                if otherStem.lowercased() == Naming.sanitiseStem(nick).lowercased() {
                    throw WorkspaceError("The nickname '\(nick)' collides with an existing outlet file.")
                }
            }
        }
        let oldURL = outlet.url
        outlet.nickname = nick
        let newURL = outletURL(for: outlet)
        outlet.url = newURL
        try outlet.save()
        if oldURL.standardizedFileURL.path != newURL.standardizedFileURL.path, fileExists(oldURL) {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    /// The outlet a record belongs to (journal articles and proceedings only).
    public func outlet(for rec: Record) -> Outlet? {
        guard Workspace.outletTypes.contains(rec.typeLabel) else { return nil }
        let name = rec.journal.pyStrip
        guard !name.isEmpty else { return nil }
        return outlets[Naming.slugifyOutlet(name)]
    }

    // MARK: - Queries

    private func byID(_ recs: [Record]) -> [Record] {
        recs.sorted { lowerKey($0.bibliothecaID) < lowerKey($1.bibliothecaID) }
    }

    public func allRecords() -> [Record] { byID(Array(records.values)) }

    public func record(_ id: String) -> Record? { records[id] }

    public func recordsByType(_ label: String) -> [Record] {
        byID(records.values.filter { $0.typeLabel == label })
    }

    /// Records with a PDF, with an EPUB, or (`nil`) with neither.
    public func recordsByFulltext(_ kind: FulltextKind?) -> [Record] {
        byID(records.values.filter { r in
            switch kind {
            case .pdf: return r.hasPDF
            case .epub: return r.hasEPUB
            case nil: return !r.hasPDF && !r.hasEPUB
            }
        })
    }

    public func recordsByDOIStatus(hasDOI: Bool) -> [Record] {
        byID(records.values.filter { !$0.doi.isEmpty == hasDOI })
    }

    public func recordsForWork(_ key: String) -> [Record] {
        guard let work = myWorks[key] else { return [] }
        return work.sortedCites().compactMap { records[$0] }
    }

    public func recordsForAuthor(_ authorID: String) -> [Record] {
        byID((authorRecords[authorID] ?? []).compactMap { records[$0] })
    }

    public func recordsForOutlet(_ outletID: String) -> [Record] {
        byID((outletRecords[outletID] ?? []).compactMap { records[$0] })
    }

    public func lookupDOI(_ doi: String) -> String? {
        doiIndex[Naming.normaliseDOI(doi).lowercased()]
    }

    /// The ACIS year letter for a record ("" when its author/year is unique).
    public func acisDisambiguator(_ rec: Record) -> String {
        if acisCache == nil || acisCache?.stamp != records.count {
            acisCache = (records.count, ACIS.disambiguatorMap(Array(records.values)))
        }
        return acisCache?.letters[rec.bibliothecaID] ?? ""
    }

    // MARK: - Notes

    public func readNotes(_ rec: Record) -> NoteFile {
        MarkdownIO.read(rec.mdURL)
    }

    /// Replace a record's notes body, preserving the frontmatter currently on
    /// disk (re-read here so a concurrent frontmatter edit is not clobbered).
    public func writeNotes(_ rec: Record, body: String) throws {
        var note = MarkdownIO.read(rec.mdURL)
        note.body = body
        try MarkdownIO.write(note, to: rec.mdURL)
        refreshModificationTimes(rec)
    }

    // MARK: - Full-text links

    /// Store (or, with `file == nil`, clear) a PDF/EPUB link. The path is
    /// relative to `storageRoot` when the file lies inside it, else absolute.
    public func setFulltextPath(_ id: String, kind: FulltextKind, file: URL?, storageRoot: URL?) throws {
        guard let rec = records[id] else { throw WorkspaceError("No record named '\(id)'.") }
        var note = MarkdownIO.read(rec.mdURL)
        if let file {
            var stored = file.path
            if let storageRoot {
                let filePath = file.resolvingSymlinksInPath().standardizedFileURL.path
                let rootPath = storageRoot.resolvingSymlinksInPath().standardizedFileURL.path
                let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                stored = filePath.hasPrefix(prefix) ? String(filePath.dropFirst(prefix.count)) : filePath
            }
            note.frontmatter[kind.rawValue] = .string(stored)
        } else {
            note.frontmatter.removeValue(forKey: kind.rawValue)
        }
        try MarkdownIO.write(note, to: rec.mdURL)
        switch kind {
        case .pdf: rec.hasPDF = file != nil
        case .epub: rec.hasEPUB = file != nil
        }
        refreshModificationTimes(rec)
        saveCache()
    }

    /// The absolute location of a record's PDF/EPUB, if one is linked.
    public func resolveFulltextPath(_ id: String, kind: FulltextKind, storageRoot: URL?) -> URL? {
        guard let rec = records[id] else { return nil }
        let note = MarkdownIO.read(rec.mdURL)
        guard let value = note.frontmatter[kind.rawValue], value.isTruthy,
              let stored = value.stringValue else { return nil }
        if stored.hasPrefix("/") { return URL(fileURLWithPath: stored) }
        if let storageRoot {
            return storageRoot.appendingPathComponent(stored).standardizedFileURL
        }
        return URL(fileURLWithPath: stored)
    }

    // MARK: - Import, rename, works

    public struct ImportResult: Equatable {
        public var imported: [String] = []
        /// (citation key, DOI, existing Bibliotheca ID) for refused duplicates.
        public var skippedDOIs: [SkippedDOI] = []
    }

    public struct SkippedDOI: Equatable {
        public var citationKey: String
        public var doi: String
        public var existingID: String
    }

    public func importBibFile(_ url: URL) throws -> ImportResult {
        guard let text = readTextLossy(url) else {
            throw WorkspaceError("Could not read \(url.lastPathComponent).")
        }
        return try importBibText(text)
    }

    /// File each entry under its citation key, skipping ids that exist and
    /// refusing entries whose DOI is already catalogued.
    public func importBibText(_ text: String) throws -> ImportResult {
        var result = ImportResult()
        for split in BibTeX.splitEntries(text) where !split.key.isEmpty {
            let id = Naming.sanitiseID(split.key)
            guard !id.isEmpty else { continue }
            let dest = bibURL(for: id)
            if fileExists(dest) || records[id] != nil { continue }
            let entryDOI = Naming.normaliseDOI(BibTeX.parseFallback(split.text)?["doi"])
            if !entryDOI.isEmpty, let existing = doiIndex[entryDOI.lowercased()] {
                result.skippedDOIs.append(SkippedDOI(citationKey: split.key, doi: entryDOI,
                                                     existingID: existing))
                continue
            }
            try writeTextAtomically(split.text.pyStrip + "\n", to: dest)
            let entry = BibTeX.parse(fileAt: dest) ?? BibEntry()
            let rec = Record(bibliothecaID: id, bibURL: dest, mdURL: mdURL(for: id), entry: entry)
            refreshModificationTimes(rec)
            records[id] = rec
            result.imported.append(id)
            if !rec.doi.isEmpty { doiIndex[rec.doi.lowercased()] = id }
        }
        if !result.imported.isEmpty {
            acisCache = nil
            buildDOIIndex()
            deriveAuthors()
            deriveOutlets()
            saveCache()
        }
        return result
    }

    /// Rename a record: move its paired files and update every work.
    public func renameRecord(_ oldID: String, to newIDRaw: String) throws {
        let newID = newIDRaw.pyStrip
        guard !newID.isEmpty else { throw WorkspaceError("New Bibliotheca ID must not be empty.") }
        if newID == oldID { return }
        guard Naming.sanitiseID(newID) == newID else {
            throw WorkspaceError("Bibliotheca ID may only contain letters, digits, hyphen and underscore.")
        }
        guard records[newID] == nil else { throw WorkspaceError("A record named '\(newID)' already exists.") }
        guard let rec = records[oldID] else { throw WorkspaceError("No record named '\(oldID)'.") }

        let newBib = bibURL(for: newID)
        let newMD = mdURL(for: newID)
        if fileExists(rec.bibURL) { try moveFile(rec.bibURL, to: newBib) }
        if fileExists(rec.mdURL) { try moveFile(rec.mdURL, to: newMD) }
        records.removeValue(forKey: oldID)
        rec.bibliothecaID = newID
        rec.bibURL = newBib
        rec.mdURL = newMD
        refreshModificationTimes(rec)
        records[newID] = rec

        for work in myWorks.values {
            var changed = false
            if work.cites.contains(oldID) {
                work.cites = work.cites.map { $0 == oldID ? newID : $0 }
                changed = true
            }
            if work.publishedAs == oldID {
                work.publishedAs = newID
                changed = true
            }
            if changed { try work.save() }
        }
        acisCache = nil
        buildDOIIndex()
        deriveAuthors()
        deriveOutlets()
        saveCache()
    }

    /// Move a file, creating the destination folder. A rename that only
    /// changes letter case goes via a temporary name, because on a
    /// case-insensitive volume (the macOS default) the destination "exists".
    private func moveFile(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if source.standardizedFileURL.path.lowercased() == destination.standardizedFileURL.path.lowercased() {
            let temporary = source.deletingLastPathComponent()
                .appendingPathComponent(".rename-\(UUID().uuidString)-\(source.lastPathComponent)")
            try fm.moveItem(at: source, to: temporary)
            try fm.moveItem(at: temporary, to: destination)
        } else {
            try fm.moveItem(at: source, to: destination)
        }
    }

    @discardableResult
    public func createMyWork(named name: String) throws -> MyWork {
        var stem = Naming.sanitiseID(name)
        if stem.isEmpty { stem = "work" }
        var candidate = stem
        var i = 2
        while myWorks[candidate] != nil
                || fileExists(myWorksDir.appendingPathComponent("\(candidate).yml")) {
            candidate = "\(stem)_\(i)"
            i += 1
        }
        let work = MyWork(key: candidate, name: name,
                          url: myWorksDir.appendingPathComponent("\(candidate).yml"))
        try work.save()
        myWorks[candidate] = work
        return work
    }

    /// Add records to a work's citations; returns how many were new.
    @discardableResult
    public func allocateToWork(_ key: String, ids: [String]) throws -> Int {
        guard let work = myWorks[key] else { throw WorkspaceError("No work named '\(key)'.") }
        var existing = Set(work.cites)
        var added = 0
        for id in ids where !id.isEmpty && !existing.contains(id) {
            work.cites.append(id)
            existing.insert(id)
            added += 1
        }
        if added > 0 { try work.save() }
        return added
    }

    // MARK: - Index cache

    private var cacheURL: URL? {
        guard let dir = cacheDirectory else { return nil }
        return dir.appendingPathComponent("index-\(stableHash(root.path)).json")
    }

    private func loadCache() -> IndexCache? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(IndexCache.self, from: data),
              cache.version == IndexCache.currentVersion, cache.root == root.path else { return nil }
        return cache
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        let cache = IndexCache(version: IndexCache.currentVersion, root: root.path,
                               records: records.values.map { CachedRecord($0) })
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// FNV-1a, so the cache file name is stable across launches (Swift's
    /// `hashValue` is randomly seeded per process).
    private func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16)
    }
}

// MARK: - Cache records

struct IndexCache: Codable {
    static let currentVersion = 1
    var version: Int
    var root: String
    var records: [CachedRecord]
}

struct CachedRecord: Codable {
    var id: String
    var bibPath: String
    var bibModified: Double
    var mdModified: Double?
    var entryType: String
    var typeLabel: String
    var author: String
    var year: String
    var title: String
    var journal: String
    var doi: String
    var hasPDF: Bool
    var hasEPUB: Bool

    init(_ r: Record) {
        id = r.bibliothecaID
        bibPath = r.bibURL.path
        bibModified = r.bibModified
        mdModified = r.mdModified
        entryType = r.entryType
        typeLabel = r.typeLabel
        author = r.author
        year = r.year
        title = r.title
        journal = r.journal
        doi = r.doi
        hasPDF = r.hasPDF
        hasEPUB = r.hasEPUB
    }

    func makeRecord(bibURL: URL, mdURL: URL) -> Record {
        let r = Record(bibliothecaID: id, bibURL: bibURL, mdURL: mdURL, entryType: entryType,
                       typeLabel: typeLabel, author: author, year: year, title: title,
                       journal: journal, doi: doi, hasPDF: hasPDF, hasEPUB: hasEPUB)
        r.bibModified = bibModified
        r.mdModified = mdModified
        return r
    }
}
