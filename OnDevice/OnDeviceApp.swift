import SwiftUI

@main
struct OnDeviceApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    appDelegate.appState = appState
                    if appDelegate.pendingURL == nil {
                        appState.showFileImporter = true
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var pendingURL: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let state = appState {
            state.showFileImporter = false
            state.processFile(url: url)
        } else {
            pendingURL = url
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Handle pending URL after state is connected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let url = self?.pendingURL, let state = self?.appState {
                state.processFile(url: url)
                self?.pendingURL = nil
            }
        }
    }
}
