import Foundation

/// Citation-style identifiers, shared with the Python app's config so the
/// meaning of a stored style id is the same everywhere.
public enum CitationStyle {
    public static let apa = "__apa__"
    public static let acis = "__acis__"
}

/// Numeric-first year sort key (so 2009 < 2025), then the raw text — a port
/// of `catalogue_sort.year_key`.
public struct YearKey: Comparable, Hashable {
    public let number: Int
    public let text: String

    public init(_ year: String) {
        let y = year.pyStrip
        let digits = y.filter(\.isASCII).filter(\.isNumber)
        number = Int(digits.prefix(18)) ?? 0
        text = y.lowercased()
    }

    public static func < (a: YearKey, b: YearKey) -> Bool {
        a.number != b.number ? a.number < b.number : a.text < b.text
    }
}

public enum CatalogueSupport {
    /// "(N)" for a positive count, "" otherwise (the sidebar count column).
    public static func countLabel(_ n: Int) -> String { n > 0 ? "(\(n))" : "" }

    /// Order J-Flags by configured priority (lower first); flags without a
    /// priority come after, alphabetically.
    public static func orderJflags(_ flags: [String], priority: [String: Double]) -> [String] {
        flags.stableSorted { a, b in
            let ka = (priority[a] == nil ? 1 : 0, priority[a] ?? 0, a.lowercased())
            let kb = (priority[b] == nil ? 1 : 0, priority[b] ?? 0, b.lowercased())
            return ka < kb
        }
    }

    /// Wrap reference markup as a minimal HTML document for the clipboard.
    public static func markupToHTML(_ markup: String) -> String {
        "<html><body>\(markup)</body></html>"
    }
}

/// A styled run of reference text.
public struct MarkupRun: Equatable {
    public var text: String
    public var italic: Bool
    public var bold: Bool

    public init(text: String, italic: Bool = false, bold: Bool = false) {
        self.text = text
        self.italic = italic
        self.bold = bold
    }
}

/// Reader for the formatter markup (`<i>`, `<b>`, HTML entities) with RTF
/// output for the rich clipboard.
public enum Markup {
    public static func runs(_ markup: String) -> [MarkupRun] {
        var runs: [MarkupRun] = []
        var italic = false
        var bold = false
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(MarkupRun(text: decodeEntities(buffer), italic: italic, bold: bold))
            buffer = ""
        }
        var i = markup.startIndex
        while i < markup.endIndex {
            let ch = markup[i]
            if ch == "<", let close = markup[i...].firstIndex(of: ">") {
                flush()
                let tag = markup[markup.index(after: i)..<close].lowercased()
                switch tag {
                case "i", "em": italic = true
                case "/i", "/em": italic = false
                case "b", "strong": bold = true
                case "/b", "/strong": bold = false
                default: break
                }
                i = markup.index(after: close)
            } else {
                buffer.append(ch)
                i = markup.index(after: i)
            }
        }
        flush()
        return runs
    }

    /// Decode the named and numeric entities the formatters emit.
    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let name = String(s[s.index(after: i)..<semi])
                if let decoded = decodeEntity(name) {
                    out += decoded
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    private static func decodeEntity(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default: break
        }
        var code: UInt32?
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            code = UInt32(name.dropFirst(2), radix: 16)
        } else if name.hasPrefix("#") {
            code = UInt32(name.dropFirst())
        }
        guard let code, let scalar = Unicode.Scalar(code) else { return nil }
        return String(Character(scalar))
    }

    /// A minimal RTF document with no font table, so pasted text takes on the
    /// destination's font and only the italics/bold are carried over.
    public static func rtf(_ markup: String) -> String {
        var body = ""
        for run in runs(markup) {
            var text = ""
            for unit in run.text.utf16 {
                switch unit {
                case 0x5C: text += "\\\\"
                case 0x7B: text += "\\{"
                case 0x7D: text += "\\}"
                case 0x0A: text += "\\line "
                case 0x20..<0x80: text += String(UnicodeScalar(UInt8(unit)))
                default: text += "\\u\(Int16(bitPattern: unit))?"
                }
            }
            var open = ""
            if run.italic { open += "\\i" }
            if run.bold { open += "\\b" }
            body += open.isEmpty ? text : "{\(open) \(text)}"
        }
        return "{\\rtf1\\ansi\\uc1 \(body)}"
    }
}
