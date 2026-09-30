import SwiftUI
import BibliothecaCore

// The small sheets opened from menus, context menus and the tab toolbars.
// Each one only collects input; the change itself is made by an AppModel
// method, which also closes the sheet (via `activeSheet = nil`).

/// Allocate records to My Works — the Mac counterpart of the GTK
/// AllocateDialog. Works that already include every record are shown ticked
/// and disabled; a new work can be created in the same step.
struct AllocateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordIDs: [String]

    @State private var chosen: Set<String> = []
    @State private var newWorkName = ""

    private var heading: String {
        recordIDs.count == 1 ? "Add \(recordIDs[0]) to:" : "Add \(recordIDs.count) records to:"
    }

    private func alreadyIncludes(_ work: MyWork) -> Bool {
        !recordIDs.isEmpty && recordIDs.allSatisfy { work.cites.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allocate to My Works")
                .font(.title2.weight(.semibold))
            Text(heading)
                .foregroundStyle(.secondary)

            if model.works.isEmpty {
                Text("You have no works yet. Name one below to create it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(model.works) { work in
                        let already = alreadyIncludes(work)
                        Toggle(isOn: Binding(
                            get: { already || chosen.contains(work.key) },
                            set: { on in
                                if on { chosen.insert(work.key) } else { chosen.remove(work.key) }
                            })) {
                            HStack {
                                Text(work.name)
                                if already {
                                    Text("already included")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(already)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }

            LabeledContent("New work:") {
                TextField("Name a new work to create", text: $newWorkName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Allocate") {
                    model.performAllocate(ids: recordIDs, to: chosen.sorted(), newWorkName: newWorkName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty && newWorkName.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }
}

/// Create a new work. When records are passed in (a record was selected),
/// offers to add them to the new work straight away.
struct NewWorkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let allocating: [String]

    @State private var name = ""
    @State private var includeRecords = true

    private var nameTaken: Bool {
        let wanted = name.trimmed.lowercased()
        return !wanted.isEmpty && model.works.contains { $0.name.lowercased() == wanted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Work")
                .font(.title2.weight(.semibold))
            Text("A work is one of your own papers, theses or projects. Allocate records to it to keep its reference list.")
                .foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            if nameTaken {
                Label("You already have a work with this name.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if !allocating.isEmpty {
                Toggle(allocating.count == 1 ? "Add \(allocating[0]) to it"
                                             : "Add the \(allocating.count) selected records to it",
                       isOn: $includeRecords)
                    .toggleStyle(.checkbox)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    model.createWork(named: name, allocating: includeRecords ? allocating : [])
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Rename a record's Bibliotheca ID, with live validation and a suggestion
/// based on the outlet nickname.
struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: String

    @State private var newID: String
    @State private var failure: String?

    init(recordID: String) {
        self.recordID = recordID
        _newID = State(initialValue: recordID)
    }

    var body: some View {
        let problem = model.renameProblem(from: recordID, to: newID)
        let candidate = newID.trimmed
        let sanitised = Naming.sanitiseID(candidate)
        let suggestion = model.suggestedID(for: recordID)

        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Bibliotheca ID")
                .font(.title2.weight(.semibold))
            Text("Renames the record\u{2019}s .bib and .md files and updates every work that cites it. The citation key inside the .bib file is not changed.")
                .foregroundStyle(.secondary)
            TextField("New Bibliotheca ID", text: $newID)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            if let problem {
                HStack {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    if !sanitised.isEmpty, sanitised != candidate {
                        Button("Use \u{201C}\(sanitised)\u{201D}") { newID = sanitised }
                            .buttonStyle(.link)
                    }
                }
                .font(.callout)
            }
            if let suggestion, suggestion != candidate {
                HStack {
                    Text("Matches the outlet nickname:")
                        .foregroundStyle(.secondary)
                    Button(suggestion) { newID = suggestion }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }
            if let failure {
                Label(failure, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    do {
                        try model.performRename(from: recordID, to: newID)
                    } catch {
                        failure = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || candidate == recordID)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

/// Set or clear an outlet's nickname.
struct NicknameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let outletID: String
    let outletName: String

    @State private var nickname: String
    @State private var failure: String?

    init(outletID: String, outletName: String, initialNickname: String) {
        self.outletID = outletID
        self.outletName = outletName
        _nickname = State(initialValue: initialNickname)
    }

    var body: some View {
        let candidate = nickname.trimmed
        let invalid = !candidate.isEmpty && !Naming.isValidNickname(candidate)

        VStack(alignment: .leading, spacing: 12) {
            Text("Outlet Nickname")
                .font(.title2.weight(.semibold))
            Text("Nickname for \u{201C}\(outletName)\u{201D}. It is shown in bold before the outlet name in the Catalogue, names the outlet\u{2019}s file, and is the usual suffix of Bibliotheca IDs (for example SmithJones2025_JBIB). Leave it blank to clear it.")
                .foregroundStyle(.secondary)
            TextField("e.g. JBIB", text: $nickname)
                .textFieldStyle(.roundedBorder)
            if invalid {
                Label("Letters A\u{2013}Z and a\u{2013}z only.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if let failure {
                Label(failure, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try model.setOutletNickname(outletID, candidate)
                    } catch {
                        failure = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(invalid)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Choose an outlet's J-Flags from the presets (Settings → J-Flags), keeping
/// any flags it already has, with a field to add a one-off flag.
struct JFlagsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let outletID: String
    let outletName: String

    @State private var options: [String]
    @State private var chosen: Set<String>
    @State private var newFlag = ""
    private let hasPresets: Bool

    init(outletID: String, outletName: String, current: [String], presets: [String]) {
        self.outletID = outletID
        self.outletName = outletName
        var seen = Set<String>()
        let all = (presets + current).filter { seen.insert($0).inserted }
        _options = State(initialValue: all)
        _chosen = State(initialValue: Set(current))
        hasPresets = !presets.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("J-Flags")
                .font(.title2.weight(.semibold))
            Text("Rating labels for \u{201C}\(outletName)\u{201D}.")
                .foregroundStyle(.secondary)

            if options.isEmpty {
                Text("No J-Flags are configured yet. Add your usual flags in Settings \u{2192} J-Flags, or add one below.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(options, id: \.self) { flag in
                        Toggle(flag, isOn: Binding(
                            get: { chosen.contains(flag) },
                            set: { on in
                                if on { chosen.insert(flag) } else { chosen.remove(flag) }
                            }))
                        .toggleStyle(.checkbox)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }

            HStack {
                TextField("Add a flag", text: $newFlag)
                    .textFieldStyle(.roundedBorder)
                // Return adds the typed flag; with the field empty it saves.
                Button("Add", action: addFlag)
                    .keyboardShortcut(newFlag.trimmed.isEmpty ? nil : .defaultAction)
                    .disabled(newFlag.trimmed.isEmpty)
            }
            if !hasPresets {
                Text("Tip: flags defined in Settings \u{2192} J-Flags are offered for every outlet and set the display order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setOutletJflags(outletID, options.filter { chosen.contains($0) })
                }
                .keyboardShortcut(newFlag.trimmed.isEmpty ? .defaultAction : nil)
            }
        }
        .padding(20)
        .frame(width: 420, height: 440)
    }

    private func addFlag() {
        let flag = newFlag.trimmed
        guard !flag.isEmpty else { return }
        if !options.contains(flag) { options.append(flag) }
        chosen.insert(flag)
        newFlag = ""
    }
}
