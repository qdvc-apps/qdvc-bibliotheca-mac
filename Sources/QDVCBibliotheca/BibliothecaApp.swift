import AppKit
import SwiftUI

@main
struct BibliothecaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // A single main window, like the GTK app (and like most Mac library
        // apps: Music, Photos, Mail's viewer window).
        Window("QDVC Bibliotheca", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 520)
                .onAppear {
                    appDelegate.model = model
                    model.startUp()
                }
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            BibliothecaCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushNotes()
    }
}
