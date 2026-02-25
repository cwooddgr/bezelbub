import SwiftUI

@main
struct BezelbubApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .onAppear {
                    appState.ensureWindowVisible = { [openWindow] in
                        openWindow(id: "main")
                    }
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
        .defaultSize(width: 1500, height: 1850)
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
