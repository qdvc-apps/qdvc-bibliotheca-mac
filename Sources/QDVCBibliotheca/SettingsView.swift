import AppKit
import SwiftUI

/// The Settings window (⌘,) — the Mac home of the GTK Preferences dialog.
struct SettingsView: View {
    @AppStorage(Prefs.Key.fulltextRoot) private var fulltextRoot = ""
    @AppStorage(Prefs.Key.reopenLast) private var reopenLast = true
    @AppStorage(Prefs.Key.notesFontSize) private var notesFontSize = Prefs.defaultNotesFontSize

    var body: some View {
        Form {
            Section {
                LabeledContent("Library folder") {
                    HStack {
                        Text(fulltextRoot.isEmpty ? "Not set"
                             : (fulltextRoot as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(fulltextRoot.isEmpty ? Color.secondary : Color.primary)
                        Button("Choose\u{2026}", action: chooseFulltextRoot)
                        if !fulltextRoot.isEmpty {
                            Button("Clear") { fulltextRoot = "" }
                        }
                    }
                }
            } header: {
                Text("Full Text")
            } footer: {
                Text("PDF and EPUB links are stored relative to this folder when the file is inside it, so the same workspace works on every machine that syncs both folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Workspace") {
                Toggle("Reopen the last workspace at launch", isOn: $reopenLast)
            }

            Section("Notes") {
                Stepper(value: $notesFontSize, in: 9...28, step: 1) {
                    Text("Font size: \(Int(notesFontSize)) pt")
                }
                Text("Notes are saved automatically a moment after you stop typing, and whenever you switch records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFulltextRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder where your PDFs and EPUBs live."
        if !fulltextRoot.isEmpty { panel.directoryURL = URL(fileURLWithPath: fulltextRoot) }
        if panel.runModal() == .OK, let url = panel.url {
            fulltextRoot = url.path
        }
    }
}
