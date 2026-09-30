import Foundation
import BibliothecaCore

/// App preferences, stored in the standard macOS defaults domain
/// (`defaults read org.qdvc.Bibliotheca`) rather than the Python app's
/// `~/.config/qdvc-bibliotheca/config.yml`. The keys that carry meaning across
/// apps (citation-style ids, J-Flag presets) use the same values.
enum Prefs {
    enum Key {
        static let fulltextRoot = "fulltextLibraryPath"
        static let reopenLast = "reopenLastWorkspace"
        static let notesFontSize = "notesFontSize"
        static let recentWorkspaces = "recentWorkspaces"
        static let lastWorkspace = "lastWorkspace"
        static let citationStyles = "citationStyles"
        static let jflagPresets = "jflagPresets"
    }

    static let defaultNotesFontSize = 13.0
    private static var defaults: UserDefaults { .standard }

    /// Folder that PDF/EPUB links are stored relative to, if set.
    static var fulltextRoot: URL? {
        let path = defaults.string(forKey: Key.fulltextRoot) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }

    static var reopenLast: Bool {
        defaults.object(forKey: Key.reopenLast) as? Bool ?? true
    }

    static var recentWorkspaces: [String] {
        get { defaults.stringArray(forKey: Key.recentWorkspaces) ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: Key.recentWorkspaces) }
    }

    static var lastWorkspace: String? {
        get { defaults.string(forKey: Key.lastWorkspace) }
        set { defaults.set(newValue, forKey: Key.lastWorkspace) }
    }

    /// Citation style id per workspace path (`__apa__`, `__acis__`, or a CSL
    /// file name), mirroring the Python `csl_styles` config key.
    static func citationStyle(for root: URL) -> String {
        let map = defaults.dictionary(forKey: Key.citationStyles) as? [String: String] ?? [:]
        return map[root.path] ?? CitationStyle.apa
    }

    static func setCitationStyle(_ style: String, for root: URL) {
        var map = defaults.dictionary(forKey: Key.citationStyles) as? [String: String] ?? [:]
        map[root.path] = style
        defaults.set(map, forKey: Key.citationStyles)
    }

    /// J-Flag presets as `[{flag, priority}]` (the same shape as the Python
    /// edition's config), edited in Settings → J-Flags.
    static var jflagPresets: [JFlagPreset] {
        get {
            guard let raw = defaults.array(forKey: Key.jflagPresets) else { return [] }
            return raw.compactMap { item -> JFlagPreset? in
                guard let dict = item as? [String: Any], let flag = dict["flag"] as? String else { return nil }
                let priority = (dict["priority"] as? NSNumber)?.doubleValue ?? 0
                return JFlagPreset(flag: flag, priority: priority)
            }
        }
        set {
            let plist = newValue.map { ["flag": $0.flag, "priority": $0.priority] as [String: Any] }
            defaults.set(plist, forKey: Key.jflagPresets)
        }
    }

    /// Flag → display priority (lower first). Blank flags are ignored.
    static func jflagPriority() -> [String: Double] {
        var map: [String: Double] = [:]
        for preset in jflagPresets {
            let flag = preset.flag.trimmingCharacters(in: .whitespaces)
            if !flag.isEmpty { map[flag] = preset.priority }
        }
        return map
    }
}

/// One configured J-Flag and its display priority.
struct JFlagPreset: Identifiable, Hashable {
    var id = UUID()
    var flag: String
    var priority: Double
}
