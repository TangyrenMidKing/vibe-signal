import SwiftUI

@main
struct AgentPulseWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchStatusView()
                .environmentObject(model)
                .onAppear { model.start() }
        }
    }
}
