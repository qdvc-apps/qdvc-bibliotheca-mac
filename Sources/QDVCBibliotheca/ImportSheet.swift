import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BibliothecaCore

/// The Import BibTeX sheet — the Mac counterpart of the GTK ImportDialog.
///
/// BibTeX can be pasted into the box (⌘V), loaded from a `.bib` file (which
/// replaces the box's text so it can be reviewed first), or arrive by
/// dropping files on the main window. The box is always what gets imported.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var sourceName: String?
    @State private var workKey: String?

    init(request: ImportRequest) {
        _text = State(initialValue: request.text)
        _sourceName = State(initialValue: request.sourceName)
        _workKey = State(initialValue: request.workKey)
    }

    private var entryCount: Int { BibTeX.splitEntries(text).count }

    private var countLabel: String {
        switch entryCount {
        case 0: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "No entries found"
        case 1: return "1 entry"
        default: return "\(entryCount) entries"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import BibTeX")
                .font(.title2.weight(.semibold))
            Text("Paste BibTeX below (\u{2318}V), or choose a .bib file. Multiple entries are supported; each is filed by its citation key. Entries whose DOI is already in the library are skipped.")
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    chooseFile()
                } label: {
                    Label("Choose File\u{2026}", systemImage: "doc")
                }
                if let sourceName {
                    Text(sourceName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(countLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            NotesEditor(text: text, documentID: "import", fontSize: 12, markdown: false) { newText in
                text = newText
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))

            Picker("Allocate imported records to:", selection: $workKey) {
                Text("None").tag(String?.none)
                if !model.works.isEmpty {
                    Divider()
                    ForEach(model.works) { work in
                        Text(work.name).tag(Optional(work.key))
                    }
                }
            }
            .disabled(model.works.isEmpty)
            .help(model.works.isEmpty ? "You have no works yet." : "Add the new records to one of your works")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    model.performImport(text: text, allocateTo: workKey)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entryCount == 0)
            }
        }
        .padding(20)
        .frame(width: 660, height: 540)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        var types: [UTType] = [.plainText]
        if let bib = UTType(filenameExtension: "bib") { types.insert(bib, at: 0) }
        panel.allowedContentTypes = types
        panel.message = "Choose one or more BibTeX files"
        panel.prompt = "Load"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var loaded: [String] = []
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) {
                loaded.append(String(decoding: data, as: UTF8.self))
            }
        }
        guard !loaded.isEmpty else {
            sourceName = "Could not read the chosen file."
            return
        }
        text = loaded.joined(separator: "\n\n")
        sourceName = panel.urls.count == 1 ? panel.urls[0].lastPathComponent : "\(panel.urls.count) files"
    }
}
