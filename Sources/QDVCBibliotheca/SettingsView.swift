import AppKit
import SwiftUI

/// The Settings window (⌘,) — the Mac home of the GTK Preferences dialog.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            JFlagSettingsView()
                .tabItem { Label("J-Flags", systemImage: "flag") }
        }
    }
}

/// Settings → General.
struct GeneralSettingsView: View {
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

/// Settings → J-Flags: the flags offered for every outlet, and their display
/// priority (lower numbers first) in the J-Flags columns.
struct JFlagSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var presets: [JFlagPreset] = Prefs.jflagPresets
    @State private var selection: Set<JFlagPreset.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("J-Flags are short rating labels for journals and proceedings, such as A* or FT50. The flags listed here are offered when you set an outlet\u{2019}s J-Flags, and appear in order of priority (lowest first); other flags follow alphabetically.")
                .foregroundStyle(.secondary)
            HStack {
                Text("Flag").font(.headline)
                Spacer()
                Text("Priority").font(.headline).frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            List(selection: $selection) {
                ForEach($presets) { $preset in
                    HStack {
                        TextField("Flag", text: $preset.flag)
                            .textFieldStyle(.plain)
                        TextField("Priority", value: $preset.priority, format: .number)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    .tag(preset.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            HStack(spacing: 2) {
                Button {
                    let next = (presets.map(\.priority).max() ?? 0) + 1
                    presets.append(JFlagPreset(flag: "", priority: next))
                } label: {
                    Image(systemName: "plus").frame(width: 20, height: 16)
                }
                .help("Add a J-Flag")
                Button {
                    presets.removeAll { selection.contains($0.id) }
                    selection = []
                } label: {
                    Image(systemName: "minus").frame(width: 20, height: 16)
                }
                .help("Remove the selected J-Flags")
                .disabled(selection.isEmpty)
                Spacer()
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .frame(width: 520, height: 400)
        .onChange(of: presets) {
            Prefs.jflagPresets = presets
            model.jflagPresetsChanged()
        }
    }
}
