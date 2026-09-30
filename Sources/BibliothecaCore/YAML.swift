import Foundation
import Yams

/// A YAML value as the workspace files use it.
///
/// Strings are kept apart from other scalars: `.scalar` holds the verbatim
/// text of a plain non-string scalar (an int, float, bool, null or timestamp)
/// so it can be written back unchanged without the app having to understand
/// every YAML type a user may hand-edit into a frontmatter block.
public indirect enum YAMLValue: Equatable {
    case string(String)
    case scalar(String)
    case sequence([YAMLValue])
    case mapping([YAMLPair])

    public static let null = YAMLValue.scalar("null")
    public static func bool(_ b: Bool) -> YAMLValue { .scalar(b ? "true" : "false") }

    /// The value as text: strings as-is, other scalars verbatim, nil for null
    /// and collections.
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .scalar(let s): return s == "null" ? nil : s
        default: return nil
        }
    }

    /// Python truthiness (`bool(value)`), which the Python app applies to
    /// frontmatter and YAML flags.
    public var isTruthy: Bool {
        switch self {
        case .string(let s):
            return !s.isEmpty
        case .scalar(let s):
            switch s {
            case "null", "false", "": return false
            default:
                if let d = Double(s.replacingOccurrences(of: "_", with: "")) { return d != 0 }
                return true
            }
        case .sequence(let items):
            return !items.isEmpty
        case .mapping(let pairs):
            return !pairs.isEmpty
        }
    }

    public var sequenceValue: [YAMLValue]? {
        if case .sequence(let items) = self { return items }
        return nil
    }

    public var mappingValue: [YAMLPair]? {
        if case .mapping(let pairs) = self { return pairs }
        return nil
    }

    /// Mapping lookup (last key wins, like a Python dict built from YAML).
    public subscript(key: String) -> YAMLValue? {
        guard case .mapping(let pairs) = self else { return nil }
        return pairs.last(where: { $0.key == key })?.value
    }
}

public struct YAMLPair: Equatable {
    public var key: String
    public var value: YAMLValue

    public init(_ key: String, _ value: YAMLValue) {
        self.key = key
        self.value = value
    }
}

// MARK: - Reading

public enum YAMLReader {
    /// Parse a YAML document. Returns nil for invalid YAML; an empty document
    /// parses as an empty mapping (PyYAML's `safe_load(...) or {}`).
    public static func parse(_ text: String) -> YAMLValue? {
        do {
            guard let node = try Yams.compose(yaml: text) else { return .mapping([]) }
            return convert(node)
        } catch {
            return nil
        }
    }

    /// Parse a document expected to be a mapping into a dictionary.
    public static func parseMapping(_ text: String) -> [String: YAMLValue]? {
        guard let value = parse(text) else { return nil }
        guard let pairs = value.mappingValue else { return [:] }
        var dict: [String: YAMLValue] = [:]
        for p in pairs { dict[p.key] = p.value }
        return dict
    }

    private static let strTag = Tag.Name.str.rawValue
    private static let nullTag = Tag.Name.null.rawValue
    private static let boolTag = Tag.Name.bool.rawValue

    static func convert(_ node: Node) -> YAMLValue {
        switch node {
        case .scalar(let scalar):
            let tag = node.tag.description
            if tag == strTag { return .string(scalar.string) }
            if tag == nullTag { return .null }
            if tag == boolTag, let b = node.bool { return .bool(b) }
            return .scalar(scalar.string)
        case .mapping(let mapping):
            var pairs: [YAMLPair] = []
            for (key, value) in mapping {
                pairs.append(YAMLPair(key.scalar?.string ?? "", convert(value)))
            }
            return .mapping(pairs)
        case .sequence(let sequence):
            return .sequence(sequence.map { convert($0) })
        default:
            return .null
        }
    }
}

// MARK: - Writing

/// A small block-style emitter that reproduces PyYAML's `safe_dump(...,
/// allow_unicode=True)` layout for the shapes the workspace uses (so files
/// written by either app look the same and don't churn under Git/Syncthing).
///
/// Known, harmless differences: strings with line breaks are written
/// double-quoted rather than folded, long plain scalars are not wrapped at 80
/// columns, and a few strings that PyYAML leaves plain (`y`, `n`, `1e5`) are
/// quoted to stay unambiguous for YAML 1.1 readers.
public enum YAMLEmitter {
    public static func document(_ pairs: [YAMLPair], sortKeys: Bool) -> String {
        guard !pairs.isEmpty else { return "{}\n" }
        var lines: [String] = []
        emitMapping(pairs, indent: 0, sortKeys: sortKeys, into: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func emitMapping(_ pairs: [YAMLPair], indent: Int, sortKeys: Bool,
                                    into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        let ordered = sortKeys ? pairs.stableSorted { $0.key < $1.key } : pairs
        for pair in ordered {
            let key = scalar(pair.key)
            switch pair.value {
            case .string(let s):
                lines.append("\(pad)\(key): \(scalar(s))")
            case .scalar(let s):
                lines.append("\(pad)\(key): \(s)")
            case .sequence(let items):
                if items.isEmpty {
                    lines.append("\(pad)\(key): []")
                } else {
                    lines.append("\(pad)\(key):")
                    emitSequence(items, indent: indent, sortKeys: sortKeys, into: &lines)
                }
            case .mapping(let sub):
                if sub.isEmpty {
                    lines.append("\(pad)\(key): {}")
                } else {
                    lines.append("\(pad)\(key):")
                    emitMapping(sub, indent: indent + 2, sortKeys: sortKeys, into: &lines)
                }
            }
        }
    }

    private static func emitSequence(_ items: [YAMLValue], indent: Int, sortKeys: Bool,
                                     into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for item in items {
            switch item {
            case .string(let s):
                lines.append("\(pad)- \(scalar(s))")
            case .scalar(let s):
                lines.append("\(pad)- \(s)")
            case .sequence(let sub):
                if sub.isEmpty {
                    lines.append("\(pad)- []")
                } else {
                    var nested: [String] = []
                    emitSequence(sub, indent: indent + 2, sortKeys: sortKeys, into: &nested)
                    appendDashed(nested, pad: pad, into: &lines)
                }
            case .mapping(let sub):
                if sub.isEmpty {
                    lines.append("\(pad)- {}")
                } else {
                    var nested: [String] = []
                    emitMapping(sub, indent: indent + 2, sortKeys: sortKeys, into: &nested)
                    appendDashed(nested, pad: pad, into: &lines)
                }
            }
        }
    }

    /// Put the first nested line on the "- " of its sequence item.
    private static func appendDashed(_ nested: [String], pad: String, into lines: inout [String]) {
        for (i, line) in nested.enumerated() {
            if i == 0 {
                lines.append(pad + "- " + String(line.dropFirst(pad.count + 2)))
            } else {
                lines.append(line)
            }
        }
    }

    // MARK: Scalars

    private static let boolLike = Rx("^(?:yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF|y|Y|n|N)\\z")
    private static let nullLike = Rx("^(?:~|null|Null|NULL)\\z")
    private static let intLike = Rx("^(?:[-+]?0b[0-1_]+|[-+]?0[0-7_]+|[-+]?(?:0|[1-9][0-9_]*)|[-+]?0x[0-9a-fA-F_]+|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)\\z")
    private static let floatLike = Rx("^(?:[-+]?(?:[0-9][0-9_]*)?\\.[0-9_]*(?:[eE][-+]?[0-9]+)?|[-+]?[0-9][0-9_]*(?:[eE][-+]?[0-9]+)|[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\\.[0-9_]*|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))\\z")
    private static let timestampLike = Rx("^[0-9][0-9][0-9][0-9]-[0-9][0-9]?-[0-9][0-9]?")

    /// Render a string scalar: plain when that round-trips as the same string,
    /// otherwise single-quoted, or double-quoted when it has line breaks or
    /// unprintable characters.
    public static func scalar(_ s: String) -> String {
        if plainAllowed(s) { return s }
        if needsDoubleQuotes(s) { return doubleQuoted(s) }
        return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func resolvesToNonString(_ s: String) -> Bool {
        boolLike.matches(s) || nullLike.matches(s) || intLike.matches(s)
            || floatLike.matches(s) || timestampLike.matches(s) || s == "<<" || s == "="
    }

    private static func isPrintable(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        if v == 0x0A || v == 0x0D { return true }
        if (0x20...0x7E).contains(v) { return true }
        if v == 0x85 || (0xA0...0xD7FF).contains(v) { return true }
        if (0xE000...0xFFFD).contains(v) && v != 0xFEFF { return true }
        return (0x10000...0x10FFFF).contains(v)
    }

    private static func isLineBreak(_ u: Unicode.Scalar) -> Bool {
        u == "\n" || u == "\r" || u.value == 0x85 || u.value == 0x2028 || u.value == 0x2029
    }

    private static func needsDoubleQuotes(_ s: String) -> Bool {
        s.unicodeScalars.contains { isLineBreak($0) || !isPrintable($0) }
    }

    private static func plainAllowed(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, let last = s.unicodeScalars.last else { return false }
        if resolvesToNonString(s) { return false }
        if first == " " || first == "\t" || last == " " || last == "\t" { return false }
        if s.hasPrefix("---") || s.hasPrefix("...") { return false }
        if "#,[]{}&*!|>'\"%@`".unicodeScalars.contains(first) { return false }
        if "-?:".unicodeScalars.contains(first) {
            let scalars = Array(s.unicodeScalars)
            if scalars.count == 1 || scalars[1] == " " { return false }
        }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return false }
        if needsDoubleQuotes(s) { return false }
        return true
    }

    private static func doubleQuoted(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case "\0": out += "\\0"
            default:
                if isPrintable(u) && !isLineBreak(u) {
                    out.unicodeScalars.append(u)
                } else if u.value <= 0xFF {
                    out += String(format: "\\x%02X", u.value)
                } else if u.value <= 0xFFFF {
                    out += String(format: "\\u%04X", u.value)
                } else {
                    out += String(format: "\\U%08X", u.value)
                }
            }
        }
        return out + "\""
    }
}
