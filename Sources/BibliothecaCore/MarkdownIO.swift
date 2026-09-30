import Foundation

/// A record's Markdown file: YAML frontmatter plus the free-form notes body.
public struct NoteFile: Equatable {
    public var frontmatter: [String: YAMLValue]
    public var body: String

    public init(frontmatter: [String: YAMLValue] = [:], body: String = "") {
        self.frontmatter = frontmatter
        self.body = body
    }
}

/// Markdown + YAML frontmatter IO — a port of `qdvc/markdown_io.py`.
///
/// ```
/// ---
/// pdf: S/SmithJones2025.pdf
/// my_works:
/// - project1
/// ---
/// Free-form Markdown notes.
/// ```
public enum MarkdownIO {
    private static let frontmatterPattern = Rx("^---\\s*\\n(.*?)\\n---\\s*\\n?(.*)$",
                                               [.dotMatchesLineSeparators])

    public static func parse(_ text: String) -> NoteFile {
        guard let m = frontmatterPattern.firstMatch(text),
              let yaml = frontmatterPattern.group(m, 1, in: text) else {
            return NoteFile(frontmatter: [:], body: text)
        }
        let body = frontmatterPattern.group(m, 2, in: text) ?? ""
        let fm = YAMLReader.parseMapping(yaml) ?? [:]
        return NoteFile(frontmatter: fm, body: body)
    }

    /// Read a note file; a missing or unreadable file is an empty note.
    public static func read(_ url: URL) -> NoteFile {
        guard fileExists(url), let text = readTextLossy(url) else { return NoteFile() }
        return parse(text)
    }

    /// Serialise frontmatter (keys sorted, as the Python app writes it) + body.
    public static func render(_ note: NoteFile) -> String {
        let pairs = note.frontmatter.map { YAMLPair($0.key, $0.value) }
        let fm = YAMLEmitter.document(pairs, sortKeys: true).pyStrip
        return "---\n\(fm)\n---\n\(note.body)"
    }

    /// Write atomically. Always re-emits the frontmatter, so callers must pass
    /// everything they want preserved (read → modify → write).
    public static func write(_ note: NoteFile, to url: URL) throws {
        try writeTextAtomically(render(note), to: url)
    }
}
