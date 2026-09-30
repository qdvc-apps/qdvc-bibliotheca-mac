import Foundation

/// A thin wrapper around `NSRegularExpression` so the ported Python helpers
/// can be written almost line-for-line. Patterns are compiled once (callers
/// keep instances in `static let`s) and a bad pattern is a programmer error.
struct Rx {
    let regex: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("Invalid regular expression \(pattern): \(error)")
        }
    }

    private func fullRange(_ s: String) -> NSRange {
        NSRange(s.startIndex..<s.endIndex, in: s)
    }

    /// `re.sub(pattern, template, s)`. Templates here are always literal text.
    func replace(_ s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, options: [], range: fullRange(s),
                                       withTemplate: template)
    }

    /// `bool(re.search(pattern, s))`.
    func matches(_ s: String) -> Bool {
        regex.firstMatch(in: s, options: [], range: fullRange(s)) != nil
    }

    /// `re.match` / `re.search` depending on whether the pattern is anchored.
    func firstMatch(_ s: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: s, options: [], range: fullRange(s))
    }

    /// Text of capture group `index` in a match, or nil if it did not take part.
    func group(_ match: NSTextCheckingResult, _ index: Int, in s: String) -> String? {
        let r = match.range(at: index)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }

    /// `re.split(pattern, s)` (no capture groups in our patterns).
    func split(_ s: String) -> [String] {
        var parts: [String] = []
        var cursor = s.startIndex
        for m in regex.matches(in: s, options: [], range: fullRange(s)) {
            guard let r = Range(m.range, in: s) else { continue }
            parts.append(String(s[cursor..<r.lowerBound]))
            cursor = r.upperBound
        }
        parts.append(String(s[cursor...]))
        return parts
    }
}

extension String {
    /// Python's `str.strip()`.
    var pyStrip: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Python's `str.strip(chars)`.
    func pyStrip(_ chars: String) -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: chars))
    }

    /// Python's `str.title()`: upper-case a cased character that follows an
    /// uncased one, lower-case every other cased character.
    var pyTitle: String {
        var out = ""
        var previousCased = false
        for ch in self {
            if ch.isCased {
                out += previousCased ? ch.lowercased() : ch.uppercased()
                previousCased = true
            } else {
                out.append(ch)
                previousCased = false
            }
        }
        return out
    }

    /// Python's whitespace `str.split()` (runs of whitespace, no empties).
    var pyWords: [String] {
        split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

extension Array {
    /// A sort that is guaranteed stable (Python's `sorted` is), used wherever
    /// the Python app relies on insertion order to break ties.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }
}

/// Case-insensitive key used wherever Python sorts with `key=str.lower`.
@inline(__always)
func lowerKey(_ s: String) -> String { s.lowercased() }

/// Atomically write UTF-8 text, creating the parent folder first (the Python
/// app writes to a `.tmp` sibling and `os.replace`s it; `.atomic` does the
/// same thing).
func writeTextAtomically(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
}

/// Read a file as UTF-8, replacing invalid sequences (Python's
/// `errors="replace"`). Returns nil when the file cannot be read at all.
func readTextLossy(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

public func fileExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

public func directoryExists(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}

/// Regular (non-hidden) files directly inside `dir` with the given extension,
/// sorted by name — the equivalent of `sorted(dir.glob("*.ext"))`.
func filesIn(_ dir: URL, withExtension ext: String) -> [URL] {
    guard let items = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]) else { return [] }
    return items
        .filter { $0.pathExtension == ext }
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}
