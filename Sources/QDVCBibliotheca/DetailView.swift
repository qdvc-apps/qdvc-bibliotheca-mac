import SwiftUI
import BibliothecaCore

/// Pane 3: the formatted reference, copy/open actions and the notes editor.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.Key.notesFontSize) private var notesFontSize = Prefs.defaultNotesFontSize

    var body: some View {
        @Bindable var model = model
        if let rec = model.selectedRecord {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(rec.bibliothecaID)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                    Picker("Citation Style", selection: $model.citationStyle) {
                        Text("APA 7").tag(CitationStyle.apa)
                        Text("ACIS").tag(CitationStyle.acis)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: model.citationStyle) { model.citationStyleChanged() }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Markup.attributed(model.referenceMarkup))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let cites = model.inText {
                            Divider()
                            InTextRow(label: "Parenthetical", text: cites.parenthetical) {
                                model.copyInText(narrative: false)
                            }
                            InTextRow(label: "Narrative", text: cites.narrative) {
                                model.copyInText(narrative: true)
                            }
                        }
                    }
                    .padding(4)
                }

                HStack {
                    Button {
                        model.copyReference(rich: true)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy the reference with formatting")
                    Button("Copy Plain") { model.copyReference(rich: false) }
                        .help("Copy the reference as plain text")
                    Spacer()
                    if model.hasFulltext(.pdf, id: rec.bibliothecaID) {
                        Button {
                            model.openFulltext(.pdf, id: rec.bibliothecaID)
                        } label: {
                            Label("Open PDF", systemImage: "doc.richtext")
                        }
                    }
                    if model.hasFulltext(.epub, id: rec.bibliothecaID) {
                        Button {
                            model.openFulltext(.epub, id: rec.bibliothecaID)
                        } label: {
                            Label("Open EPUB", systemImage: "book")
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Notes").font(.headline)
                    Spacer()
                    Text(model.notesDirty ? "Edited" : "Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NotesEditor(text: model.notesText,
                            documentID: model.notesRecordID,
                            fontSize: notesFontSize) { newText in
                    model.notesEdited(newText)
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                .layoutPriority(1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("No Record Selected", systemImage: "text.book.closed",
                                   description: Text("Select a record to see its reference and notes."))
        }
    }
}

private struct InTextRow: View {
    let label: String
    let text: String
    let copy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(text).textSelection(.enabled)
            Spacer()
            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(label.lowercased()) citation")
        }
    }
}
