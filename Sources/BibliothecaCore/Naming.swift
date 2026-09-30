import Foundation

/// Identifier, slug and DOI helpers — a direct port of `qdvc/naming.py`.
///
/// These decide file names on disk, so they must stay byte-for-byte
/// compatible with the Python app (the parity tests check this).
public enum Naming {
    private static let idDisallowed = Rx("[^A-Za-z0-9_-]+")
    private static let whitespaceRun = Rx("\\s+")
    private static let doiPrefix = Rx("^https?://(dx\\.)?doi\\.org/", [.caseInsensitive])
    private static let nonAlnum = Rx("[^A-Za-z0-9]+")
    private static let nonLowerAlnum = Rx("[^a-z0-9]+")
    private static let nicknamePattern = Rx("^[A-Za-z]+\\z")

    /// Strip a leading `https://doi.org/` (or `dx.doi.org`) prefix and
    /// surrounding whitespace. Returns "" for nil/empty input.
    public static func normaliseDOI(_ doi: String?) -> String {
        guard let doi, !doi.isEmpty else { return "" }
        return doiPrefix.replace(doi.pyStrip, with: "")
    }

    /// Turn arbitrary text into a safe file stem / Bibliotheca ID.
    public static func sanitiseID(_ text: String?) -> String {
        var t = (text ?? "").pyStrip
        t = whitespaceRun.replace(t, with: "_")
        t = idDisallowed.replace(t, with: "")
        return t.pyStrip("_-")
    }

    /// The text after the last underscore (`AuthorSurnamesYear_suffix`), or "".
    public static func idSuffix(_ bibliothecaID: String) -> String {
        guard let idx = bibliothecaID.lastIndex(of: "_") else { return "" }
        return String(bibliothecaID[bibliothecaID.index(after: idx)...]).pyStrip
    }

    /// A safe file stem that preserves case (used for nickname file names).
    public static func sanitiseStem(_ text: String?) -> String {
        var t = (text ?? "").pyStrip
        t = whitespaceRun.replace(t, with: "-")
        t = idDisallowed.replace(t, with: "")
        return t.pyStrip("-_")
    }

    /// "Journal of Bibliotheca" → "journal-of-bibliotheca" (the stable outlet id).
    public static func slugifyOutlet(_ name: String?) -> String {
        let t = (name ?? "").pyStrip.lowercased()
        return nonLowerAlnum.replace(t, with: "-").pyStrip("-")
    }

    /// `SURNAME_GivenNames`, or "" when there is no usable surname.
    public static func makeAuthorID(surname: String?, givenNames: String?) -> String {
        let surname = (surname ?? "").pyStrip
        let given = (givenNames ?? "").pyStrip
        guard !surname.isEmpty else { return "" }
        let sur = nonAlnum.replace(surname, with: "").uppercased()
        let giv = nonAlnum.replace(given.pyTitle, with: "")
        guard !sur.isEmpty else { return "" }
        return giv.isEmpty ? sur : "\(sur)_\(giv)"
    }

    /// An outlet nickname may contain only the ASCII letters A–Z and a–z.
    public static func isValidNickname(_ nickname: String) -> Bool {
        nicknamePattern.matches(nickname)
    }
}
