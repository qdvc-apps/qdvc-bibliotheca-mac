import SwiftUI
import BibliothecaCore

/// The DOI Lookup tab: is this DOI already in the library? A match jumps
/// straight to the record in the Catalogue, as in the GTK app.
struct DOILookupView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Text("DOI Lookup")
                .font(.title2.weight(.semibold))
            Text("Check whether a DOI is already in your library. A bare DOI and a doi.org link both work.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("e.g. 10.1234/example", text: $model.doiQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($fieldFocused)
                    .onSubmit { model.lookupDOI() }
                Button("Look Up") { model.lookupDOI() }
                    .disabled(model.doiQuery.trimmed.isEmpty)
            }
            if let outcome = model.doiOutcome {
                outcomeView(outcome)
            }
        }
        .padding(32)
        .frame(maxWidth: 600, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: DOILookupOutcome) -> some View {
        switch outcome {
        case .found(let id):
            HStack {
                Label("Found \(id).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Show in Catalogue") { model.revealRecord(id) }
            }
        case .notFound(let doi):
            HStack {
                Label("No record has the DOI \(doi).", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import BibTeX\u{2026}") { model.beginImport() }
            }
        case .empty:
            Label("Enter a DOI to look up.", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}
