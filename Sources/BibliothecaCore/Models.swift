import Foundation

/// One catalogued work — a port of `models.Record`.
///
/// The index fields are eager (cached between launches); the full BibTeX
/// entry is parsed lazily on first use.
public final class Record: Identifiable {
    public var id: String { bibliothecaID }

    public internal(set) var bibliothecaID: String
    public internal(set) var bibURL: URL
    public internal(set) var mdURL: URL
    public internal(set) var entryType: String
    public internal(set) var typeLabel: String
    public internal(set) var author: String
    public internal(set) var year: String
    public internal(set) var title: String
    public internal(set) var journal: String
    public internal(set) var doi: String
    public internal(set) var hasPDF: Bool
    public internal(set) var hasEPUB: Bool

    /// File modification times, used to validate the index cache.
    var bibModified: Double = 0
    var mdModified: Double?

    var cachedEntry: BibEntry?

    init(bibliothecaID: String, bibURL: URL, mdURL: URL, entryType: String = "misc",
         typeLabel: String = "Other", author: String = "", year: String = "",
         title: String = "", journal: String = "", doi: String = "",
         hasPDF: Bool = false, hasEPUB: Bool = false) {
        self.bibliothecaID = bibliothecaID
        self.bibURL = bibURL
        self.mdURL = mdURL
        self.entryType = entryType
        self.typeLabel = typeLabel
        self.author = author
        self.year = year
        self.title = title
        self.journal = journal
        self.doi = doi
        self.hasPDF = hasPDF
        self.hasEPUB = hasEPUB
    }

    /// Build the index fields from a parsed entry (what `_scan` and
    /// `import_bib_text` do in Python).
    convenience init(bibliothecaID: String, bibURL: URL, mdURL: URL, entry e: BibEntry,
                     hasPDF: Bool = false, hasEPUB: Bool = false) {
        let type = e.entryType.isEmpty ? "misc" : e.entryType.lowercased()
        self.init(bibliothecaID: bibliothecaID, bibURL: bibURL, mdURL: mdURL,
                  entryType: type,
                  typeLabel: Builtin.typeLabel(type, booktitle: e["booktitle"]),
                  author: Builtin.clean(e.first("author", "editor")),
                  year: Builtin.clean(e["year"]),
                  title: Builtin.clean(e["title"]),
                  journal: Builtin.clean(e.first("journal", "journaltitle", "booktitle")),
                  doi: Naming.normaliseDOI(e["doi"]),
                  hasPDF: hasPDF, hasEPUB: hasEPUB)
        cachedEntry = e
    }

    /// The parsed BibTeX entry (parsed on first access, then cached).
    public func entry() -> BibEntry {
        if let e = cachedEntry { return e }
        let e = BibTeX.parse(fileAt: bibURL) ?? BibEntry()
        cachedEntry = e
        return e
    }

    /// Drop the cached entry so the next `entry()` re-reads the file.
    public func invalidateEntry() { cachedEntry = nil }

    /// The Outlet column: the journal for articles, the container title for
    /// chapters and proceedings, an em dash otherwise.
    public var outlet: String {
        switch typeLabel {
        case "Journal article", "Book chapter", "Proceedings":
            return journal.isEmpty ? "\u{2014}" : journal
        default:
            return "\u{2014}"
        }
    }

    public func apaMarkup() -> String { APA7.markup(entry()) }
    public func apaPlain() -> String { APA7.plain(entry()) }

    public func acisMarkup(disambiguator: String = "") -> String {
        ACIS.markup(entry(), disambiguator: disambiguator)
    }

    public func acisPlain(disambiguator: String = "") -> String {
        ACIS.plain(entry(), disambiguator: disambiguator)
    }

    public func acisInText(disambiguator: String = "", narrative: Bool = false) -> String {
        ACIS.inTextPlain(entry(), disambiguator: disambiguator, narrative: narrative)
    }
}

/// One of the user's own papers/projects and the records it cites — a port
/// of `models.MyWork`. `key` is the YAML file stem.
public final class MyWork: Identifiable {
    public var id: String { key }
    public let key: String
    public internal(set) var name: String
    public internal(set) var url: URL
    public internal(set) var cites: [String]
    public internal(set) var publishedAs: String?

    init(key: String, name: String, url: URL, cites: [String] = [], publishedAs: String? = nil) {
        self.key = key
        self.name = name
        self.url = url
        self.cites = cites
        self.publishedAs = publishedAs
    }

    /// De-duplicated, case-insensitively sorted citations.
    public func sortedCites() -> [String] {
        var seen = Set<String>()
        let unique = cites.filter { seen.insert($0).inserted }
        return unique.stableSorted { lowerKey($0) < lowerKey($1) }
    }

    /// Canonical on-disk form: name, cites, then optional published_as.
    func yamlPairs() -> [YAMLPair] {
        var pairs = [YAMLPair("name", .string(name)),
                     YAMLPair("cites", .sequence(sortedCites().map { YAMLValue.string($0) }))]
        if let publishedAs, !publishedAs.isEmpty {
            pairs.append(YAMLPair("published_as", .string(publishedAs)))
        }
        return pairs
    }

    func save() throws {
        cites = sortedCites()
        try writeTextAtomically(YAMLEmitter.document(yamlPairs(), sortKeys: false), to: url)
    }
}

/// An author derived from the BibTeX — a port of `models.Author`. Only
/// `starred` is user state; the rest is regenerated.
public final class Author: Identifiable {
    public var id: String { authorID }
    public let authorID: String
    public internal(set) var surname: String
    public internal(set) var givenNames: String
    public internal(set) var starred: Bool
    public internal(set) var url: URL
    public internal(set) var recordIDs: [String] = []

    init(authorID: String, surname: String, givenNames: String, starred: Bool = false, url: URL) {
        self.authorID = authorID
        self.surname = surname
        self.givenNames = givenNames
        self.starred = starred
        self.url = url
    }

    public var displayName: String {
        givenNames.isEmpty ? surname : "\(surname), \(givenNames)"
    }

    func save() throws {
        let pairs = [YAMLPair("id", .string(authorID)),
                     YAMLPair("surname", .string(surname)),
                     YAMLPair("given_names", .string(givenNames)),
                     YAMLPair("starred", .bool(starred))]
        try writeTextAtomically(YAMLEmitter.document(pairs, sortKeys: true), to: url)
    }
}

/// A journal or proceedings outlet — a port of `models.Outlet`.
///
/// `outletID` is the slug of the full name and never changes; the file stem
/// follows the nickname when one is set.
public final class Outlet: Identifiable {
    public var id: String { outletID }
    public let outletID: String
    public internal(set) var name: String
    public internal(set) var nickname: String
    public internal(set) var starred: Bool
    public internal(set) var jflags: [String]
    public internal(set) var url: URL
    public internal(set) var recordIDs: [String] = []

    init(outletID: String, name: String, nickname: String = "", starred: Bool = false,
         jflags: [String] = [], url: URL) {
        self.outletID = outletID
        self.name = name
        self.nickname = nickname
        self.starred = starred
        self.jflags = jflags
        self.url = url
    }

    public var displayName: String { name }

    /// De-duplicated, alphabetical J-Flags (the canonical on-disk order).
    public func sortedJflags() -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for f in jflags {
            let flag = f.pyStrip
            if !flag.isEmpty, seen.insert(flag).inserted { unique.append(flag) }
        }
        return unique.stableSorted { lowerKey($0) < lowerKey($1) }
    }

    func save() throws {
        jflags = sortedJflags()
        var pairs = [YAMLPair("name", .string(name))]
        if !nickname.isEmpty { pairs.append(YAMLPair("nickname", .string(nickname))) }
        pairs.append(YAMLPair("starred", .bool(starred)))
        pairs.append(YAMLPair("jflags", .sequence(jflags.map { YAMLValue.string($0) })))
        try writeTextAtomically(YAMLEmitter.document(pairs, sortKeys: false), to: url)
    }
}
