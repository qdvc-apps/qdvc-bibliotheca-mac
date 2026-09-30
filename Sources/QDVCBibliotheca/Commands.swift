import AppKit
import SwiftUI
import BibliothecaCore

extension KeyEquivalent {
    /// F2, the GTK app's Rename shortcut.
    static let f2 = KeyEquivalent(Character(Unicode.Scalar(UInt32(NSF2FunctionKey))!))
}

extension AppTab {
    /// ⌘1…⌘4, in tab order.
    var shortcut: KeyEquivalent {
        switch self {
        case .catalogue: return "1"
        case .authors: return "2"
        case .outlets: return "3"
        case .doiLookup: return "4"
        }
    }
}

/// Menu-bar commands. Standard items (Edit, Window, Help, Settings…, Quit,
/// Hide) come from the system; these add the workspace and record actions.
struct BibliothecaCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.self) { path in
                    Button((path as NSString).abbreviatingWithTildeInPath) {
                        model.open(URL(fileURLWithPath: path, isDirectory: true))
                    }
                }
                if !model.recentWorkspaces.isEmpty {
                    Divider()
                    Button("Clear Menu") { model.clearRecents() }
                }
            }
            Divider()
            Button("New Work\u{2026}") {
                let selected = model.currentTab == .catalogue ? model.selectedID : nil
                model.beginNewWork(allocating: selected.map { [$0] } ?? [])
            }
            .keyboardShortcut("n")
            .disabled(model.workspace == nil || model.isLoading)
            Button("Import BibTeX\u{2026}") { model.beginImport() }
                .keyboardShortcut("i")
                .disabled(model.workspace == nil || model.isLoading)
            Divider()
            Button("Close Workspace") { model.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
        }

        CommandGroup(after: .toolbar) {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) { model.currentTab = tab }
                    .keyboardShortcut(tab.shortcut)
                    .disabled(model.workspace == nil)
            }
            Divider()
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.workspace == nil)
            Button("Rescan All Files") { model.refresh(fullRescan: true) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
            Divider()
        }

        CommandMenu("Record") {
            // Record commands act on the Catalogue selection, so only there.
            let id = model.currentTab == .catalogue ? model.selectedID : nil
            Button("Open PDF") { model.openFulltext(.pdf, id: id) }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.hasFulltext(.pdf, id: id))
            Button("Open EPUB") { model.openFulltext(.epub, id: id) }
                .disabled(!model.hasFulltext(.epub, id: id))
            Button("Quick Look") { model.quickLook(id) }
                .keyboardShortcut("y")
                .disabled(!model.hasFulltext(.pdf, id: id) && !model.hasFulltext(.epub, id: id))
            Divider()
            Button("Copy Reference") { model.copyReference(rich: true) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(id == nil)
            Button("Copy Reference as Plain Text") { model.copyReference(rich: false) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(id == nil)
            Button("Copy Bibliotheca ID") { model.copyID(id) }
                .disabled(id == nil)
            Divider()
            Button("Allocate to My Works\u{2026}") { model.beginAllocate(id.map { [$0] } ?? []) }
                .disabled(id == nil)
            Button("Rename Bibliotheca ID\u{2026}") { model.beginRename(id) }
                .keyboardShortcut(.f2, modifiers: [])
                .disabled(id == nil)
            Button("Show Outlet") { model.revealOutlet(model.outletID(forRecord: id)) }
                .disabled(model.outletID(forRecord: id) == nil)
            Divider()
            Button("Reveal .bib in Finder") { model.revealInFinder(id, markdown: false) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(id == nil)
            Button("Open .md in Text Editor") { model.openInTextEditor(id, markdown: true) }
                .disabled(id == nil)
            Divider()
            Button("Link PDF\u{2026}") { model.attachFulltext(.pdf, id: id) }
                .disabled(id == nil)
            Button("Link EPUB\u{2026}") { model.attachFulltext(.epub, id: id) }
                .disabled(id == nil)
        }
    }
}
