import SwiftUI

@main
struct BezelbubApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    // Delay briefly so onOpenURL can fire first when
                    // the app is launched by dropping a file on the dock.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if appState.screenshotImage == nil {
                            appState.showFileImporter = true
                        }
                    }
                }
                .onOpenURL { url in
                    appState.showFileImporter = false
                    appState.processFile(url: url)
                }
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .defaultSize(width: 1500, height: 1850)
    }
}
