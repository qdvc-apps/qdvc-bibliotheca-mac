import XCTest
@testable import BibliothecaCore

/// Checks BibliothecaCore against reference outputs recorded in
/// `Fixtures/parity.json`, which were produced by the Python/GTK edition of
/// QDVC Bibliotheca. The fixture is committed, so these tests need nothing
/// else; see docs/MAINTENANCE.md §5 for how to regenerate it.
final class ParityTests: XCTestCase {
    private static let fixtures: Fixtures = {
        guard let url = Bundle.module.url(forResource: "parity", withExtension: "json",
                                          subdirectory: "Fixtures") else {
            fatalError("parity.json missing from test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not decode parity.json: \(error)")
        }
    }()

    private var fx: Fixtures { Self.fixtures }

    func testBibParsingAndIndexFields() {
        for c in fx.bib {
            let entry = BibTeX.parseFallback(c.text)
            guard let expected = c.parsed else {
                XCTAssertNil(entry, c.name)
                continue
            }
            guard let entry else {
                XCTFail("\(c.name): no entry parsed")
                continue
            }
            XCTAssertEqual(entry.entryType, expected.entryType, c.name)
            XCTAssertEqual(entry.citationKey, expected.citationKey, c.name)
            XCTAssertEqual(entry.fields, expected.fields, c.name)

            if let index = c.index {
                let rec = Record(bibliothecaID: "X", bibURL: URL(fileURLWithPath: "/x.bib"),
                                 mdURL: URL(fileURLWithPath: "/x.md"), entry: entry)
                XCTAssertEqual(rec.typeLabel, index.typeLabel, c.name)
                XCTAssertEqual(rec.author, index.author, c.name)
                XCTAssertEqual(rec.year, index.year, c.name)
                XCTAssertEqual(rec.title, index.title, c.name)
                XCTAssertEqual(rec.journal, index.journal, c.name)
                XCTAssertEqual(rec.doi, index.doi, c.name)
            }
        }
    }

    func testAPA7() {
        for c in fx.bib {
            guard let entry = BibTeX.parseFallback(c.text) else { continue }
            XCTAssertEqual(APA7.markup(entry), c.apaMarkup, c.name)
            XCTAssertEqual(APA7.plain(entry), c.apaPlain, c.name)
            XCTAssertEqual(APA7.formatAuthorList(entry["author"] ?? ""), c.apaAuthorList, c.name)
        }
    }

    func testACIS() {
        for c in fx.bib {
            guard let entry = BibTeX.parseFallback(c.text) else { continue }
            XCTAssertEqual(ACIS.markup(entry, disambiguator: "b"), c.acisMarkup, c.name)
            XCTAssertEqual(ACIS.plain(entry), c.acisPlain, c.name)
            XCTAssertEqual(ACIS.inTextPlain(entry, disambiguator: "a"), c.acisInText, c.name)
            XCTAssertEqual(ACIS.inTextPlain(entry, narrative: true), c.acisInTextNarrative, c.name)
            XCTAssertEqual(ACIS.formatAuthorList(entry["author"] ?? ""), c.acisAuthorList, c.name)
        }
    }

    func testSplitEntries() {
        for c in fx.split {
            let got = BibTeX.splitEntries(c.text)
            XCTAssertEqual(got.map(\.text), c.entries.map(\.text))
            XCTAssertEqual(got.map(\.key), c.entries.map(\.key))
        }
    }

    func testNaming() {
        for c in fx.naming {
            XCTAssertEqual(Naming.sanitiseID(c.input), c.sanitiseID, "sanitiseID(\(c.input))")
            XCTAssertEqual(Naming.sanitiseStem(c.input), c.sanitiseStem, "sanitiseStem(\(c.input))")
            XCTAssertEqual(Naming.slugifyOutlet(c.input), c.slugifyOutlet, "slugify(\(c.input))")
            XCTAssertEqual(Naming.idSuffix(c.input), c.idSuffix, "idSuffix(\(c.input))")
            XCTAssertEqual(Naming.normaliseDOI(c.input), c.normaliseDOI, "normaliseDOI(\(c.input))")
        }
        for c in fx.authorIDs {
            XCTAssertEqual(Naming.makeAuthorID(surname: c.surname, givenNames: c.given), c.expected,
                           "\(c.surname), \(c.given)")
        }
        for c in fx.nicknames {
            XCTAssertEqual(Naming.isValidNickname(c.input), c.valid, c.input)
        }
    }

    func testNameSplitting() {
        for c in fx.nameSplits {
            let parts = Builtin.splitName(c.input)
            XCTAssertEqual(parts.surname, c.surname, c.input)
            XCTAssertEqual(parts.given, c.given, c.input)
            XCTAssertEqual(Builtin.surnameInitials(c.input), c.surnameInitials, c.input)
        }
    }

    func testYAMLScalarQuoting() {
        for c in fx.yamlScalars {
            XCTAssertEqual(YAMLEmitter.scalar(c.value), c.expected, "scalar(\(c.value))")
            // And whatever we write must read back as the same string.
            let doc = YAMLEmitter.document([YAMLPair("k", .string(c.value))], sortKeys: false)
            XCTAssertEqual(YAMLReader.parse(doc)?["k"], .string(c.value), "round-trip \(c.value)")
        }
    }

    func testYAMLDocuments() {
        for c in fx.yamlDocuments {
            let pairs = c.pairs.map { pair -> YAMLPair in
                YAMLPair(pair.key, pair.value.yamlValue)
            }
            XCTAssertEqual(YAMLEmitter.document(pairs, sortKeys: c.sortKeys), c.expected)
        }
    }

    func testMarkdownParsing() {
        for c in fx.markdown {
            let note = MarkdownIO.parse(c.text)
            XCTAssertEqual(note.frontmatter.keys.sorted(), c.keys, c.text)
            for (key, value) in c.strings {
                XCTAssertEqual(note.frontmatter[key], .string(value), c.text)
            }
            XCTAssertEqual(note.body, c.body, c.text)
        }
    }

    func testDisambiguation() {
        let records = fx.disambiguation.records.map {
            Record(bibliothecaID: $0.bibliothecaID, bibURL: URL(fileURLWithPath: "/x.bib"),
                   mdURL: URL(fileURLWithPath: "/x.md"), author: $0.author, year: $0.year,
                   title: $0.title)
        }
        XCTAssertEqual(ACIS.disambiguatorMap(records), fx.disambiguation.expected)
        for (n, letters) in fx.disambiguation.letters {
            XCTAssertEqual(ACIS.letter(Int(n)!), letters, n)
        }
    }

    func testMiscHelpers() {
        for (n, label) in fx.misc.countLabels {
            XCTAssertEqual(CatalogueSupport.countLabel(Int(n)!), label)
        }
        let jf = fx.misc.orderJflags
        XCTAssertEqual(CatalogueSupport.orderJflags(jf.flags, priority: jf.priority), jf.expected)
        for c in fx.misc.markupToPlain {
            XCTAssertEqual(Builtin.markupToPlain(c.input), c.expected, c.input)
        }
        for c in fx.misc.typeLabels {
            XCTAssertEqual(Builtin.typeLabel(c.type, booktitle: c.booktitle), c.expected, c.type)
        }
    }
}

// MARK: - Fixture schema

private struct Fixtures: Decodable {
    var bib: [BibCase]
    var split: [SplitCase]
    var naming: [NamingCase]
    var authorIDs: [AuthorIDCase]
    var nicknames: [NicknameCase]
    var nameSplits: [NameSplitCase]
    var yamlScalars: [YAMLScalarCase]
    var yamlDocuments: [YAMLDocumentCase]
    var markdown: [MarkdownCase]
    var disambiguation: DisambiguationCase
    var misc: MiscCase

    enum CodingKeys: String, CodingKey {
        case bib, split, naming, nicknames, markdown, disambiguation, misc
        case authorIDs = "author_ids"
        case nameSplits = "name_splits"
        case yamlScalars = "yaml_scalars"
        case yamlDocuments = "yaml_documents"
    }
}

private struct ParsedEntry: Decodable {
    var entryType: String
    var citationKey: String?
    var fields: [String: String]

    enum CodingKeys: String, CodingKey {
        case fields
        case entryType = "entry_type"
        case citationKey = "citation_key"
    }
}

private struct IndexFields: Decodable {
    var typeLabel, author, year, title, journal, doi: String

    enum CodingKeys: String, CodingKey {
        case author, year, title, journal, doi
        case typeLabel = "type_label"
    }
}

private struct BibCase: Decodable {
    var name: String
    var text: String
    var parsed: ParsedEntry?
    var index: IndexFields?
    var apaMarkup, apaPlain, acisMarkup, acisPlain: String?
    var acisInText, acisInTextNarrative, apaAuthorList, acisAuthorList: String?

    enum CodingKeys: String, CodingKey {
        case name, text, parsed, index
        case apaMarkup = "apa_markup"
        case apaPlain = "apa_plain"
        case acisMarkup = "acis_markup"
        case acisPlain = "acis_plain"
        case acisInText = "acis_in_text"
        case acisInTextNarrative = "acis_in_text_narrative"
        case apaAuthorList = "apa_author_list"
        case acisAuthorList = "acis_author_list"
    }
}

private struct SplitCase: Decodable {
    struct Entry: Decodable { var text: String; var key: String }
    var text: String
    var entries: [Entry]
}

private struct NamingCase: Decodable {
    var input, sanitiseID, sanitiseStem, slugifyOutlet, idSuffix, normaliseDOI: String

    enum CodingKeys: String, CodingKey {
        case input
        case sanitiseID = "sanitise_id"
        case sanitiseStem = "sanitise_stem"
        case slugifyOutlet = "slugify_outlet"
        case idSuffix = "id_suffix"
        case normaliseDOI = "normalise_doi"
    }
}

private struct AuthorIDCase: Decodable { var surname, given, expected: String }
private struct NicknameCase: Decodable { var input: String; var valid: Bool }

private struct NameSplitCase: Decodable {
    var input, surname, given, surnameInitials: String

    enum CodingKeys: String, CodingKey {
        case input, surname, given
        case surnameInitials = "surname_initials"
    }
}

private struct YAMLScalarCase: Decodable { var value, expected: String }

/// A JSON scalar/array as used in the fixture's YAML documents.
private enum JSONValue: Decodable {
    case string(String)
    case bool(Bool)
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .array(try c.decode([JSONValue].self))
        }
    }

    var yamlValue: YAMLValue {
        switch self {
        case .string(let s): return .string(s)
        case .bool(let b): return .bool(b)
        case .array(let items): return .sequence(items.map(\.yamlValue))
        }
    }
}

private struct YAMLDocumentCase: Decodable {
    struct Pair: Decodable {
        var key: String
        var value: JSONValue

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            key = try c.decode(String.self)
            value = try c.decode(JSONValue.self)
        }
    }

    var sortKeys: Bool
    var pairs: [Pair]
    var expected: String

    enum CodingKeys: String, CodingKey {
        case pairs, expected
        case sortKeys = "sort_keys"
    }
}

private struct MarkdownCase: Decodable {
    var text: String
    var keys: [String]
    var strings: [String: String]
    var body: String
}

private struct DisambiguationCase: Decodable {
    struct Rec: Decodable {
        var bibliothecaID, author, year, title: String

        enum CodingKeys: String, CodingKey {
            case author, year, title
            case bibliothecaID = "bibliotheca_id"
        }
    }

    var records: [Rec]
    var expected: [String: String]
    var letters: [String: String]
}

private struct MiscCase: Decodable {
    struct OrderJflags: Decodable {
        var flags: [String]
        var priority: [String: Double]
        var expected: [String]
    }

    struct StringCase: Decodable { var input, expected: String }

    struct TypeLabelCase: Decodable {
        var type: String
        var booktitle: String?
        var expected: String
    }

    var countLabels: [String: String]
    var orderJflags: OrderJflags
    var markupToPlain: [StringCase]
    var typeLabels: [TypeLabelCase]

    enum CodingKeys: String, CodingKey {
        case countLabels = "count_labels"
        case orderJflags = "order_jflags"
        case markupToPlain = "markup_to_plain"
        case typeLabels = "type_labels"
    }
}
