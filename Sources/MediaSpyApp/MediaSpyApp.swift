import AppKit
import SwiftUI

// MediaSpy — native media inspector (info only, no playback).
// Ember design: design/MediaSpy Ember.dc.html.

@main
struct MediaSpyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .onAppear {
                    // Dev convenience: MEDIASPY_OPEN=$'path1\npath2' .build/debug/MediaSpyApp
                    // (Files must NOT be argv: positional arguments make SwiftUI
                    // wait for scene routing and no window is ever created.)
                    if let joined = ProcessInfo.processInfo.environment["MEDIASPY_OPEN"] {
                        let paths = joined.split(separator: "\n").map(String.init)
                        state.add(paths.map { URL(fileURLWithPath: $0) })
                    }
                }
                // Finder "Open With" / `open -a MediaSpy file` route here.
                .onOpenURL { url in
                    if url.isFileURL { state.add([url]) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 780)
        // Claim ALL external launch events. Without this, launching with file
        // arguments leaves SwiftUI waiting for a scene to route them to and
        // NO window is ever created (empirically verified — see plan).
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { state.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Report") { state.copyReport() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button(state.inspectorMode == .curated ? "Show All Fields" : "Show Summary") {
                    state.inspectorMode = state.inspectorMode == .curated ? .allFields : .curated
                }
                .keyboardShortcut("l")
                .disabled(state.selectedItem?.report == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Retain the provider ourselves — NSApp.servicesProvider is unowned in practice.
    private let serviceProvider = MediaInfoServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Wire up the "Get Media Info" right-click Finder Service (M3).
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        NSApp.activate(ignoringOtherApps: true)
    }
}
