import AppKit
import SwiftUI

@main
struct OpenPixelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()

    var body: some Scene {
        Window("OpenPixel", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 650)
                .tint(Palette.accent)
                .onAppear {
                    delegate.store = store
                    store.start()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1120, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Image") { store.newImage() }
                    .keyboardShortcut("n")
                    .disabled(store.operation.isBusy)
                Button("Save Image As…") { store.saveImage() }
                    .keyboardShortcut("s")
                    .disabled(store.selection == nil)
            }
            CommandMenu("Model") {
                Button("Manage Models…") { store.showModels = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Cancel Current Task") { store.cancel() }
                    .keyboardShortcut(".")
                    .disabled(!store.operation.canCancel)
            }
            CommandGroup(replacing: .help) {
                Button("Open Image Library") { store.openLibrary() }
                Button("Open Diagnostic Logs") { store.openLogs() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.shutdown()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

