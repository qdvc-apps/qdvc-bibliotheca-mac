import XCTest
@testable import BibliothecaCore

/// End-to-end tests of the workspace model on a scratch folder, covering the
/// file-format contract shared with the Python app.
final class WorkspaceTests: XCTestCase {
    private var root: URL!
    private var cacheDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("bibliotheca-tests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("ws", isDirectory: true)
        cacheDir = base.appendingPathComponent("cache", isDirectory: true)
        try Workspace.initialise(at: root)
        try write("bibtex/S/SmithJones2025_JBIB.bib", """
            @article{SmithJones2025_JBIB,
              author = {Smith, John and Jones, Beatrice},
              title = {Knowledge Work},
              journal = {Journal of Bibliotheca},
              year = {2025},
              doi = {10.1234/jbib.1}
            }
            """)
        try write("bibtex/S/Smith2025.bib", """
            @inproceedings{Smith2025,
              author = {Smith, John and Smith, John},
              title = {Duplicated Author},
              booktitle = {Proceedings of ICIS},
              year = {2025}
            }
            """)
        try write("bibtex/Z/Zuboff2019.bib", """
            @book{Zuboff2019,
              author = {Zuboff, Shoshana},
              title = {Surveillance Capitalism},
              publisher = {PublicAffairs},
              year = {2019}
            }
            """)
        try write("markdown/S/SmithJones2025_JBIB.md", "---\npdf: S/SmithJones2025.pdf\n---\nGreat paper.\n")
        try write("my_works/thesis.yml", "cites:\n- Zuboff2019\n- SmithJones2025_JBIB\n- Zuboff2019\nname: My Thesis\n")
        try write("bibtex/.stversions/S/Old.bib", "@misc{Old, title = {Should be ignored}}")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func loaded() -> Workspace {
        let ws = Workspace(root: root, cacheDirectory: cacheDir)
        ws.load()
        return ws
    }

    func testLoadAndQueries() {
        let ws = loaded()
        XCTAssertEqual(ws.allRecords().map(\.bibliothecaID), ["Smith2025", "SmithJones2025_JBIB", "Zuboff2019"])
        XCTAssertEqual(ws.recordsByType("Journal article").map(\.bibliothecaID), ["SmithJones2025_JBIB"])
        XCTAssertEqual(ws.recordsByFulltext(.pdf).map(\.bibliothecaID), ["SmithJones2025_JBIB"])
        XCTAssertEqual(ws.recordsByFulltext(nil).count, 2)
        XCTAssertEqual(ws.recordsByDOIStatus(hasDOI: true).count, 1)
        XCTAssertEqual(ws.lookupDOI("https://doi.org/10.1234/JBIB.1"), "SmithJones2025_JBIB")
        XCTAssertEqual(ws.record("SmithJones2025_JBIB")?.outlet, "Journal of Bibliotheca")
        XCTAssertEqual(ws.record("Zuboff2019")?.outlet, "\u{2014}")
    }

    func testAuthorsDerivedAndPersisted() throws {
        let ws = loaded()
        XCTAssertEqual(ws.allAuthors().map(\.authorID), ["JONES_Beatrice", "SMITH_John", "ZUBOFF_Shoshana"])
        // An author listed twice on one record counts that record once.
        XCTAssertEqual(ws.authors["SMITH_John"]?.recordIDs, ["Smith2025", "SmithJones2025_JBIB"])
        XCTAssertEqual(try read("authors/ZUBOFF_Shoshana.yml"),
                       "given_names: Shoshana\nid: ZUBOFF_Shoshana\nstarred: false\nsurname: Zuboff\n")

        try ws.setAuthorStarred("ZUBOFF_Shoshana", true)
        let again = loaded()
        XCTAssertEqual(again.starredAuthors().map(\.authorID), ["ZUBOFF_Shoshana"])
    }

    func testOutletsNicknameAndJflags() throws {
        let ws = loaded()
        XCTAssertEqual(ws.allOutlets().map(\.outletID), ["journal-of-bibliotheca", "proceedings-of-icis"])
        XCTAssertTrue(fileExists(root.appendingPathComponent("outlets/journal-of-bibliotheca.yml")))

        try ws.setOutletJflags("journal-of-bibliotheca", ["FT50", "A*", "FT50"])
        try ws.setOutletNickname("journal-of-bibliotheca", "JBIB")
        XCTAssertFalse(fileExists(root.appendingPathComponent("outlets/journal-of-bibliotheca.yml")))
        XCTAssertEqual(try read("outlets/JBIB.yml"),
                       "name: Journal of Bibliotheca\nnickname: JBIB\nstarred: false\njflags:\n- A*\n- FT50\n")

        XCTAssertThrowsError(try ws.setOutletNickname("proceedings-of-icis", "jbib"))
        XCTAssertThrowsError(try ws.setOutletNickname("proceedings-of-icis", "IC IS"))

        let again = loaded()
        XCTAssertEqual(again.outlets["journal-of-bibliotheca"]?.nickname, "JBIB")
        XCTAssertEqual(again.outlets["journal-of-bibliotheca"]?.jflags, ["A*", "FT50"])
    }

    func testMyWorksCanonicalisedOnLoad() throws {
        let ws = loaded()
        XCTAssertEqual(ws.myWorks["thesis"]?.name, "My Thesis")
        XCTAssertEqual(try read("my_works/thesis.yml"),
                       "name: My Thesis\ncites:\n- SmithJones2025_JBIB\n- Zuboff2019\n")
        XCTAssertEqual(ws.recordsForWork("thesis").map(\.bibliothecaID), ["SmithJones2025_JBIB", "Zuboff2019"])

        try write("my_works/broken.yml", "name: [unclosed\n")
        _ = loaded()
        XCTAssertEqual(try read("my_works/broken.yml"), "name: [unclosed\n", "unparseable YAML is left alone")
    }

    func testNotesPreserveFrontmatter() throws {
        let ws = loaded()
        let rec = try XCTUnwrap(ws.record("SmithJones2025_JBIB"))
        XCTAssertEqual(ws.readNotes(rec).body, "Great paper.\n")
        try ws.writeNotes(rec, body: "Updated.\n")
        XCTAssertEqual(try read("markdown/S/SmithJones2025_JBIB.md"),
                       "---\npdf: S/SmithJones2025.pdf\n---\nUpdated.\n")

        let fresh = try XCTUnwrap(ws.record("Zuboff2019"))
        try ws.writeNotes(fresh, body: "New note")
        XCTAssertEqual(try read("markdown/Z/Zuboff2019.md"), "---\n{}\n---\nNew note")
    }

    func testFulltextLinksRelativeToStorageRoot() throws {
        let ws = loaded()
        let library = root.deletingLastPathComponent().appendingPathComponent("library", isDirectory: true)
        let pdf = library.appendingPathComponent("Z/Zuboff2019.pdf")
        try FileManager.default.createDirectory(at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF-1.4".utf8).write(to: pdf)

        try ws.setFulltextPath("Zuboff2019", kind: .pdf, file: pdf, storageRoot: library)
        XCTAssertEqual(ws.readNotes(try XCTUnwrap(ws.record("Zuboff2019"))).frontmatter["pdf"],
                       .string("Z/Zuboff2019.pdf"))
        XCTAssertEqual(ws.record("Zuboff2019")?.hasPDF, true)
        XCTAssertEqual(ws.resolveFulltextPath("Zuboff2019", kind: .pdf, storageRoot: library)?.path,
                       pdf.standardizedFileURL.path)

        try ws.setFulltextPath("Zuboff2019", kind: .pdf, file: nil, storageRoot: library)
        XCTAssertEqual(ws.record("Zuboff2019")?.hasPDF, false)
        XCTAssertNil(ws.resolveFulltextPath("Zuboff2019", kind: .pdf, storageRoot: library))
    }

    func testCacheIsIncremental() throws {
        _ = loaded()
        try write("bibtex/A/Added2024.bib", "@misc{Added2024, title = {Added Later}, year = {2024}}")
        try write("markdown/Z/Zuboff2019.md", "---\nepub: Z/Zuboff2019.epub\n---\n")
        let ws = loaded()
        XCTAssertNotNil(ws.record("Added2024"), "new files appear without a full rescan")
        XCTAssertEqual(ws.record("Zuboff2019")?.hasEPUB, true, "changed notes are re-read")
    }

    func testImportRenameAndValidate() throws {
        let ws = loaded()
        let result = try ws.importBibText("""
            @article{New2026, author = {New, Nora}, title = {Fresh}, journal = {JBIB}, year = {2026}}
            @article{Dup2025, title = {Same DOI}, doi = {https://doi.org/10.1234/JBIB.1}}
            @article{Zuboff2019, title = {Existing id}}
            """)
        XCTAssertEqual(result.imported, ["New2026"])
        XCTAssertEqual(result.skippedDOIs, [Workspace.SkippedDOI(citationKey: "Dup2025", doi: "10.1234/JBIB.1",
                                                                  existingID: "SmithJones2025_JBIB")])
        XCTAssertTrue(fileExists(root.appendingPathComponent("bibtex/N/New2026.bib")))

        try ws.renameRecord("Zuboff2019", to: "Zuboff2019_PA")
        XCTAssertNil(ws.record("Zuboff2019"))
        XCTAssertTrue(fileExists(root.appendingPathComponent("bibtex/Z/Zuboff2019_PA.bib")))
        XCTAssertEqual(try read("my_works/thesis.yml"),
                       "name: My Thesis\ncites:\n- SmithJones2025_JBIB\n- Zuboff2019_PA\n")
        XCTAssertThrowsError(try ws.renameRecord("New2026", to: "bad id!"))

        let report = ws.validate(storageRoot: nil)
        XCTAssertEqual(report.keyMismatch.map { $0.id }, ["Zuboff2019_PA"])
        XCTAssertEqual(report.missingFulltext.map { $0.id }, ["SmithJones2025_JBIB"])
        XCTAssertTrue(report.formatted().contains("BibTeX key does not match Bibliotheca ID (1):"))
    }

    func testCreateAndAllocateWork() throws {
        let ws = loaded()
        let work = try ws.createMyWork(named: "Grant Proposal")
        XCTAssertEqual(work.key, "Grant_Proposal")
        XCTAssertEqual(try ws.allocateToWork(work.key, ids: ["Zuboff2019", "Smith2025", "Zuboff2019"]), 2)
        XCTAssertEqual(try read("my_works/Grant_Proposal.yml"),
                       "name: Grant Proposal\ncites:\n- Smith2025\n- Zuboff2019\n")
    }
}
