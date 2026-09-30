import AppKit
import BibliothecaCore

/// Thin wrappers over AppKit services (the Mac counterpart of
/// `qdvc/platform_utils.py` and the GTK clipboard owner).
enum Platform {
    static func copyPlain(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Put a reference on the pasteboard as HTML, RTF and plain text, so it
    /// pastes with italics into Word, Pages, Mail, Google Docs and so on.
    static func copyRich(markup: String, plain: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(CatalogueSupport.markupToHTML(markup), forType: .html)
        pb.setData(Data(Markup.rtf(markup).utf8), forType: .rtf)
        pb.setString(plain, forType: .string)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open a file in the user's default plain-text editor (`open -t`).
    static func openInTextEditor(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", url.path]
        try? process.run()
    }
}

extension Markup {
    /// Formatter markup as an AttributedString that SwiftUI `Text` renders
    /// with italics/bold.
    static func attributed(_ markup: String) -> AttributedString {
        var out = AttributedString()
        for run in runs(markup) {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.italic { intent.insert(.emphasized) }
            if run.bold { intent.insert(.stronglyEmphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            out.append(piece)
        }
        return out
    }
}
