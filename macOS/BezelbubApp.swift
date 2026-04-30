import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct BezelbubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .onAppear {
                    // Delay briefly so onOpenURL can fire first when
                    // the app is launched by dropping a file on the dock.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if appState.screenshotImage == nil {
                            appState.showOpenPanel()
                        }
                    }
                }
                .onOpenURL { url in
                    appState.processFile(url: url)
                }
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .defaultSize(width: 800, height: 1000)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appState.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
