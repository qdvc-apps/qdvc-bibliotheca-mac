import Foundation

/// Workspace integrity problems — a port of `Workspace.validate` and
/// `ui_prefs.format_validation_report`.
public struct ValidationReport: Equatable {
    public var orphanMarkdown: [String] = []
    public var keyMismatch: [(id: String, key: String)] = []
    public var missingFulltext: [(id: String, kind: String, path: String)] = []
    public var danglingCitations: [(work: String, id: String)] = []
    public var danglingPublishedAs: [(work: String, id: String)] = []
    public var duplicateDOIs: [(doi: String, ids: [String])] = []
    public var nickSetNoSuffix: [(id: String, nickname: String)] = []
    public var nickSetSuffixDiff: [(id: String, suffix: String, nickname: String)] = []
    public var suffixNoNick: [(id: String, suffix: String)] = []

    public var problemCount: Int {
        orphanMarkdown.count + keyMismatch.count + missingFulltext.count
            + danglingCitations.count + danglingPublishedAs.count + duplicateDOIs.count
            + nickSetNoSuffix.count + nickSetSuffixDiff.count + suffixNoNick.count
    }

    public static func == (a: ValidationReport, b: ValidationReport) -> Bool {
        a.formatted() == b.formatted()
    }

    /// Plain-text rendering, identical to the Python app's report.
    public func formatted() -> String {
        guard problemCount > 0 else { return "No problems found. The workspace looks healthy." }
        var lines: [String] = []
        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("\(title) (\(items.count)):")
            lines.append(contentsOf: items.map { "  \u{2022} \($0)" })
            lines.append("")
        }
        section("Orphan Markdown files (no matching .bib)", orphanMarkdown)
        section("BibTeX key does not match Bibliotheca ID",
                keyMismatch.map { "\($0.id)  (key is '\($0.key)')" })
        section("Missing full-text files",
                missingFulltext.map { "\($0.id) [\($0.kind)] \u{2192} \($0.path)" })
        section("Citations to unknown records",
                danglingCitations.map { "work '\($0.work)' cites missing '\($0.id)'" })
        section("'published_as' pointing to unknown records",
                danglingPublishedAs.map { "work '\($0.work)' \u{2192} missing '\($0.id)'" })
        section("Duplicate DOIs",
                duplicateDOIs.map { "\($0.doi) \u{2192} \($0.ids.joined(separator: ", "))" })
        section("Outlet nickname set, but Bibliotheca ID has no suffix",
                nickSetNoSuffix.map { "\($0.id)  (outlet nickname is '\($0.nickname)')" })
        section("Outlet nickname set, but Bibliotheca ID suffix differs",
                nickSetSuffixDiff.map { "\($0.id)  (suffix '\($0.suffix)' \u{2260} nickname '\($0.nickname)')" })
        section("Bibliotheca ID has a suffix, but no outlet nickname is set",
                suffixNoNick.map { "\($0.id)  (suffix is '\($0.suffix)')" })
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Workspace {
    public func validate(storageRoot: URL?) -> ValidationReport {
        var report = ValidationReport()
        let sortedRecords = allRecords()

        for rec in sortedRecords {
            let e = rec.entry()
            let key = (e.citationKey ?? e["id"] ?? "").pyStrip
            if !key.isEmpty, key != rec.bibliothecaID {
                report.keyMismatch.append((rec.bibliothecaID, key))
            }
        }

        if directoryExists(markdownDir),
           let walker = FileManager.default.enumerator(at: markdownDir, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]) {
            var orphans: [String] = []
            for case let url as URL in walker where url.pathExtension == "md" {
                if record(url.deletingPathExtension().lastPathComponent) == nil {
                    orphans.append(url.path)
                }
            }
            report.orphanMarkdown = orphans.sorted()
        }

        for rec in sortedRecords where fileExists(rec.mdURL) {
            let note = readNotes(rec)
            for kind in FulltextKind.allCases {
                guard let value = note.frontmatter[kind.rawValue], value.isTruthy,
                      let stored = value.stringValue else { continue }
                var url = URL(fileURLWithPath: stored)
                if !stored.hasPrefix("/"), let storageRoot {
                    url = storageRoot.appendingPathComponent(stored)
                }
                if !fileExists(url) {
                    report.missingFulltext.append((rec.bibliothecaID, kind.label, stored))
                }
            }
        }

        for work in myWorks.values.sorted(by: { lowerKey($0.name) < lowerKey($1.name) }) {
            for c in work.cites where record(c) == nil {
                report.danglingCitations.append((work.name, c))
            }
            if let p = work.publishedAs, !p.isEmpty, record(p) == nil {
                report.danglingPublishedAs.append((work.name, p))
            }
        }

        var byDOI: [String: [String]] = [:]
        for rec in sortedRecords where !rec.doi.isEmpty {
            byDOI[rec.doi.lowercased(), default: []].append(rec.bibliothecaID)
        }
        for (doi, ids) in byDOI.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
            report.duplicateDOIs.append((doi, ids.sorted()))
        }

        for rec in sortedRecords {
            guard let outlet = outlet(for: rec) else { continue }
            let suffix = Naming.idSuffix(rec.bibliothecaID)
            let nick = outlet.nickname.pyStrip
            if !nick.isEmpty {
                if suffix.isEmpty {
                    report.nickSetNoSuffix.append((rec.bibliothecaID, nick))
                } else if suffix != nick {
                    report.nickSetSuffixDiff.append((rec.bibliothecaID, suffix, nick))
                }
            } else if !suffix.isEmpty {
                report.suffixNoNick.append((rec.bibliothecaID, suffix))
            }
        }
        return report
    }
}
